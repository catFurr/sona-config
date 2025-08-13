--[[
Meeting Hosts for Sonacove MUC (Component module)

Ensures first eligible (logged-in) creator becomes host, host handover on leave, and timed destruction if no host remains.

- On join, if there is no host and the joining user is logged in, promote them to affiliation 'owner' (moderator role). Any scheduled destruction is canceled on join.
- When the last non-admin owner leaves, promote any logged-in participant to owner. If no eligible participant exists, schedule room destruction after a configurable delay.

Configuration:
- meeting_host_destroy_delay (number, seconds): Delay before attempting to destroy a room with no host (default: 120).
- Module should be enabled under the conference MUC component:
  Component "conference.${XMPP_DOMAIN}" "muc"
      modules_enabled = {
          ...
          "meeting_host";
      }

]]

local jid = require 'util.jid';
local jid_host = jid.host;
local socket = require 'socket';
local st = require 'util.stanza';

local util = module:require 'util';
local is_admin = util.is_admin;
local is_healthcheck_room = util.is_healthcheck_room;
local get_room_from_jid = util.get_room_from_jid;
local ends_with = util.ends_with;

local system_chat = module:require 'mod_system_chat';

local muc_domain_base = module:get_option_string('muc_mapper_domain_base');
local destroy_delay_seconds = module:get_option_number('meeting_host_destroy_delay', 120);


-- Helpers
local function is_focus_occupant(occupant)
    return occupant and occupant.nick and ends_with(occupant.nick, '/focus');
end

local function occupant_is_logged_in(occupant, session)
    -- Treat JWT-auth and local auth users as logged in; fallback to domain check
    if session and (session.auth_token or session.username) then
        return true;
    end
    if occupant and occupant.bare_jid and muc_domain_base then
        return jid_host(occupant.bare_jid) == muc_domain_base;
    end
    return false;
end

local function has_non_admin_owner(room)
    for _, o in room:each_occupant() do
        if not is_admin(o.bare_jid) and not is_focus_occupant(o) then
            local aff = room:get_affiliation(o.bare_jid);
            if aff == 'owner' then
                return true;
            end
        end
    end
    return false;
end

local function find_logged_in_candidate(room)
    for _, o in room:each_occupant() do
        if not is_admin(o.bare_jid) and not is_focus_occupant(o) then
            if occupant_is_logged_in(o) then
                return o;
            end
        end
    end
    return nil;
end

local function promote_owner(room, occupant)
    if occupant and occupant.bare_jid then
        room:set_affiliation(true, occupant.bare_jid, 'owner');
    end
end

local function schedule_room_destruction(room)
    if not room then return end
    if is_healthcheck_room(room.jid) then return end

    -- If a destruction is already scheduled, don't schedule another
    if room._data.meeting_host_destroy_at then
        return;
    end

    room._data.meeting_host_destroy_at = socket.gettime() + destroy_delay_seconds;
    local target_room_jid = room.jid;

    module:log('info', 'Scheduling room destruction for %s in %ds', target_room_jid, destroy_delay_seconds);
    
    -- Notify all participants that the meeting will end soon
    local minutes = math.floor(destroy_delay_seconds / 60);
    local seconds = destroy_delay_seconds % 60;
    local time_message;
    if minutes > 0 and seconds > 0 then
        time_message = string.format("%d minute%s and %d second%s", 
            minutes, minutes == 1 and "" or "s", 
            seconds, seconds == 1 and "" or "s");
    elseif minutes > 0 then
        time_message = string.format("%d minute%s", minutes, minutes == 1 and "" or "s");
    else
        time_message = string.format("%d second%s", seconds, seconds == 1 and "" or "s");
    end
    
    local warning_message = string.format(
        "⚠️ This meeting will automatically end in %s due to no moderator being present. " ..
        "A moderator can join to prevent this from happening.",
        time_message
    );
    
    system_chat.send_to_all(room, warning_message, "System");

    local function try_destroy()
        local now = socket.gettime();
        local target_room = get_room_from_jid(target_room_jid);

        if not target_room then
            return;
        end

        local destroy_at = target_room._data and target_room._data.meeting_host_destroy_at;
        if not destroy_at then
            return; -- cancelled
        end

        if now < destroy_at then
            -- Too early; re-check shortly to be resilient to clock drift (1s)
            module:add_timer(1, try_destroy);
            return;
        end

        if has_non_admin_owner(target_room) then
            target_room._data.meeting_host_destroy_at = nil;
            -- Notify participants that destruction was cancelled due to moderator presence
            system_chat.send_to_all(target_room, 
                "✅ A moderator is present. The automatic meeting end has been cancelled.",
                "System");
            return;
        end

        module:log('info', 'Destroying room %s due to no moderator present', target_room_jid);
        prosody.events.fire_event('maybe-destroy-room', {
            room = target_room;
            reason = 'no-moderator-present';
            caller = module:get_name();
        });
        -- Clear the schedule regardless
        target_room._data.meeting_host_destroy_at = nil;
    end

    module:add_timer(destroy_delay_seconds, try_destroy);
end

-- Events
module:hook('muc-occupant-joined', function (event)
    local room, occupant, session = event.room, event.occupant, event.origin;

    if is_healthcheck_room(room.jid) or is_admin(occupant.bare_jid) or is_focus_occupant(occupant) then
        return;
    end

    -- If there is no non-admin owner and the joiner is logged in, promote them
    if not has_non_admin_owner(room) and occupant_is_logged_in(occupant, session) then
        promote_owner(room, occupant);

        -- Cancel any scheduled destruction on join
        if room._data.meeting_host_destroy_at then
            room._data.meeting_host_destroy_at = nil;
            module:log('info', 'Cancelled scheduled room destruction for %s (participant joined)', room.jid);

            system_chat.send_to_all(room, 
                "✅ A moderator has joined the meeting. The automatic meeting end has been cancelled.",
                "System");
        end
    end
end, 2); -- run before av moderation, filesharing, breakout and polls

module:hook('muc-occupant-left', function (event)
    local room, leaving_occupant = event.room, event.occupant;

    if is_healthcheck_room(room.jid) then
        return;
    end

    -- Compute if any other non-admin owner will remain after this occupant leaves
    local another_owner_exists = false;
    for _, o in room:each_occupant() do
        if o ~= leaving_occupant and not is_admin(o.bare_jid) and not is_focus_occupant(o) then
            local aff = room:get_affiliation(o.bare_jid);
            if aff == 'owner' then
                another_owner_exists = true;
                break;
            end
        end
    end

    if another_owner_exists then
        return;
    end

    -- No other owners; try to promote a logged-in user, otherwise schedule destruction
    local candidate = find_logged_in_candidate(room);
    if candidate then
        module:log('debug', 'Promoting logged-in participant %s to owner in %s', candidate.bare_jid or 'unknown', room.jid);
        promote_owner(room, candidate);
        return;
    end

    -- schedule_room_destruction(room);
end, -1); -- run after breakout rooms


