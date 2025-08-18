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
local socket = require 'socket';
local st = require 'util.stanza';

local util = module:require 'util';
local is_admin = util.is_admin;
local is_healthcheck_room = util.is_healthcheck_room;
local get_room_from_jid = util.get_room_from_jid;

local system_chat = module:require 'mod_system_chat';

local destroy_delay_seconds = module:get_option_number('meeting_host_destroy_delay', 120);


-- Helpers
local function is_subbed_user(session)
    -- Get user context from session
    local ctx_user = session and session.jitsi_meet_context_user;
    local sub_status = ctx_user and ctx_user.subscription_status;

    if sub_status == 'active' or sub_status == 'trialing' then
        return true;
    end
    return false;
end

local function has_host(room)
    for _, o in room:each_occupant() do
        local aff = room:get_affiliation(o.bare_jid);
        if aff == 'owner' and not is_admin(o.bare_jid) then
            return true;
        end
    end
    return false;
end

local function find_host_candidate(room)
    for _, occupant in room:each_occupant() do
        local bare_jid = occupant.bare_jid;
        local domain = jid.host(bare_jid);
        local username = jid.node(bare_jid);

        local user_sessions = prosody.hosts[domain] and prosody.hosts[domain].sessions;
        local user_session = user_sessions and user_sessions[username];

        if user_session then
            for resource, session in pairs(user_session.sessions) do
                if is_subbed_user(session) then
                    return occupant;
                end
            end
        end
    end
    return nil;
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

        if has_host(target_room) then
            target_room._data.meeting_host_destroy_at = nil;
            -- Notify participants that destruction was cancelled due to moderator presence
            system_chat.send_to_all(target_room, 
                "✅ A moderator is present. The automatic meeting end has been cancelled.",
                "System");
            return;
        end

        module:log('info', 'Destroying room %s due to no moderator present', target_room_jid);
        module:fire_event('maybe-destroy-room', {
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
module:hook('muc-room-pre-create', function (event)
    local session, stanza = event.origin, event.stanza;

    local user_jid = stanza.attr.from;
    if is_admin(user_jid) then
        return;
    end

    -- Subscription check (active or trialing)
    if not is_subbed_user(session) then
        session.send(st.error_reply(
                stanza,
                'cancel',
                'not-allowed',
                'no active subscription found'
            ));
        return true;
    end

end, 99); -- before anything else

module:hook('muc-occupant-pre-join', function (event)
    local room, occupant, session, stanza = event.room, event.occupant, event.origin, event.stanza;

    if is_admin(occupant.bare_jid) then
        return;
    end

    -- Are we the first non-system occupant? (room creation)
    for _, o in room:each_occupant() do
        if not is_admin(o.bare_jid) then
            -- module:log('debug', 'Room %s already has occupants, skipping subscription check', room.jid);
            return;
        end
    end

    -- Subscription check (active or trialing)
    if not is_subbed_user(session) then
        session.send(st.error_reply(
                stanza,
                'cancel',
                'not-allowed',
                'no active subscription found'
            ));
        return true;
    end

end, 99); -- before anything else

module:hook('muc-occupant-joined', function (event)
    local room, occupant, session = event.room, event.occupant, event.origin;

    if is_healthcheck_room(room.jid) or is_admin(occupant.bare_jid) then
        return;
    end

    -- If there is no host and we are subbed user, promote user
    if not has_host(room) and is_subbed_user(session) then
        room:set_affiliation(true, occupant.bare_jid, 'owner');

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
    local room, occupant, session = event.room, event.occupant, event.origin;

    if is_healthcheck_room(room.jid) or is_admin(occupant.bare_jid) then
        return;
    end

    if not is_subbed_user(session) or has_host(room) then
        return;
    end

    -- No other owners; try to promote a subbed user, otherwise schedule destruction
    local candidate = find_host_candidate(room);
    if candidate then
        module:log('debug', 'Promoting subbed participant %s to owner in %s', candidate.bare_jid or 'unknown', room.jid);
        room:set_affiliation(true, candidate.bare_jid, 'owner');
        return;
    end

    -- schedule_room_destruction(room);
end, -1); -- run after breakout rooms


