--[[
Meeting Hosts for Sonacove MUC (Component module)

Ensures first eligible (logged-in) creator becomes host, host handover on leave, and timed destruction if no host remains.

-- This will prevent anyone joining the call till jicofo and one host join the room
-- for the rest of the participants lobby will be turned on and they will be waiting there till
-- the main participant joins and lobby will be turned off at that time and rest of the participants will
-- join the room.
- On join, if there is no host and the joining user is logged in, promote them to affiliation 'owner' (moderator role). Any scheduled destruction is canceled on join.
- When the last non-admin owner leaves, promote any logged-in participant to owner. If no eligible participant exists, schedule room destruction after a configurable delay.

-- This module depends on mod_persistent_lobby.

Component "conference.${XMPP_DOMAIN}" "muc"
    modules_enabled = {
        ...
        "meeting_host";
    }
    meeting_host_destroy_delay = 120
]]

local jid = require 'util.jid';
local socket = require 'socket';
local st = require 'util.stanza';

local system_chat = module:require 'mod_system_chat';
local util = module:require "util";
local is_admin = util.is_admin;
local is_healthcheck_room = util.is_healthcheck_room;
local get_room_from_jid = util.get_room_from_jid;
local process_host_module = util.process_host_module;

local destroy_delay_seconds = module:get_option_number('meeting_host_destroy_delay', 120);
local muc_domain_base = module:get_option_string('muc_mapper_domain_base');
if not muc_domain_base then
    module:log('warn', "No 'muc_mapper_domain_base' option set, disabling module");
    return
end

local lobby_muc_component_config = 'lobby.' .. muc_domain_base;
local lobby_host;


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

-- if not authenticated user is trying to join the room we enable lobby in it
-- and wait for the moderator to join
module:hook('muc-occupant-pre-join', function (event)
    local room, occupant, session = event.room, event.occupant, event.origin;

    -- session._data.valid_room_host is set in mod_reservations

    -- we ignore jicofo as we want it to join the room or if the room has already seen its
    -- authenticated host
    if is_admin(occupant.bare_jid) or is_healthcheck_room(room.jid) or room._data.has_host then
        return;
    end

    if (session._data.valid_room_host) then
        room:set_affiliation(true, occupant.bare_jid, 'owner');
        room._data.has_host = true;

        -- Cancel any scheduled destruction on join
        -- if room._data.meeting_host_destroy_at then
        --     room._data.meeting_host_destroy_at = nil;
        --     module:log('info', 'Cancelled scheduled room destruction for %s (participant joined)', room.jid);

        --     system_chat.send_to_all(room, 
        --         "✅ A moderator has joined the meeting. The automatic meeting end has been cancelled.",
        --         "System");
        -- end

        if room:get_members_only() then
            -- the host is here, let's drop the lobby
            room:set_members_only(false);
            lobby_host:fire_event('destroy-lobby-room', {
                room = room,
                newjid = room.jid,
                message = 'Host arrived.',
            });
        end
    end

    if not room:get_members_only() then
        -- let's enable lobby
        module:log('info', 'Will wait for host in %s.', room.jid);
        prosody.events.fire_event('create-persistent-lobby-room', {
            room = room;
            reason = 'waiting-for-host',
            -- skip_display_name_check = true;
        });
    end

end);

process_host_module(lobby_muc_component_config, function(host_module, host)
    -- lobby muc component created
    module:log('info', 'Lobby component loaded %s', host);
    lobby_host = module:context(host_module);
end);

module:hook('muc-occupant-left', function (event)
    local room, occupant, session = event.room, event.occupant, event.origin;

    if is_healthcheck_room(room.jid) or is_admin(occupant.bare_jid) then
        return;
    end

    if not is_subbed_user(session) or has_host(room) or not room:has_occupant() then
        return;
    end

    -- No other owners; try to promote a subbed user, otherwise schedule destruction
    -- FIXME run this async so we don't block this event
    local candidate = find_host_candidate(room);
    if candidate then
        module:log('debug', 'Promoting subbed participant %s to owner in %s', candidate.bare_jid or 'unknown', room.jid);
        room:set_affiliation(true, candidate.bare_jid, 'owner');
        return;
    end

    -- schedule_room_destruction(room);
end, -1); -- after persistent_lobby


