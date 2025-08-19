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

local socket = require 'socket';
local timer = require 'util.timer';

local async_check_host = module:require 'mod_host_check';
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
local function has_host(room)
    for _, o in room:each_occupant() do
        local aff = room:get_affiliation(o.bare_jid);
        if aff == 'owner' and not is_admin(o.bare_jid) then
            return true;
        end
    end
    return false;
end

local function has_non_system_occupant(room)
    for _, o in room:each_occupant() do
        if not is_admin(o.bare_jid) then
            return true;
        end
    end
    return false;
end

local function schedule_room_destruction(room)
    if not room or is_healthcheck_room(room.jid) then return end

    -- If a destruction is already scheduled, don't schedule another
    if room._data.meeting_host_destroy_at then return end

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
        "⚠️ This meeting will end in %s due to no Host being present. " ..
        "Host can join to prevent this from happening.",
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
            return 1;
        end

        if has_host(target_room) then
            target_room._data.meeting_host_destroy_at = nil;
            -- Notify participants that destruction was cancelled due to moderator presence
            system_chat.send_to_all(room,
                "✅ The meeting has a new Host. The automatic room close has been cancelled.",
                "System");
            return;
        end

        module:log('info', 'Destroying room %s due to no host present', target_room_jid);
        module:fire_event('maybe-destroy-room', {
            room = target_room,
            reason = 'no-moderator-present',
            caller = module:get_name(),
        });
        -- Clear the schedule regardless
        target_room._data.meeting_host_destroy_at = nil;
    end

    timer.add_task(destroy_delay_seconds, try_destroy);
end

local function host_check_success(event)
    local room, occupant, session = event.room, event.occupant, event.session;
    if not room._data or room._data.has_host then
        return;
    end

    room._data.has_host = true;

    room:set_affiliation(true, occupant.bare_jid, 'owner');
    occupant.role = room:get_default_role(room:get_affiliation(occupant.bare_jid)) or 'moderator';

    -- Send private message to the new host about whiteboard functionality
    system_chat.send_to_participant(room,
        "You are the meeting host. Please use excalidraw.com for whiteboard functionality.",
        occupant.jid,
        "System");

    -- TODO
    if has_non_system_occupant(room) then
        -- HOST is in the room already
        -- we should never get here if the host is not in this room (if user is in lobby dont consider in room)


        -- We are in an existing meeting. don't change the lobby settings.

        -- Cancel any scheduled destruction on join
        if room._data.meeting_host_destroy_at then
            room._data.meeting_host_destroy_at = nil;
            module:log('info', 'Cancelled scheduled room destruction for %s (participant joined)', room.jid);

            system_chat.send_to_all(room,
                "✅ The meeting has a new Host. The automatic room close has been cancelled.",
                "System");
        end
    elseif room:get_members_only() then
        -- Empty room, let's bring everyone in and destroy the lobby
        room:set_members_only(false);

        -- the host is here, let's drop the lobby
        module:fire_event('room_host_arrived', room.jid, session);
        lobby_host:fire_event('destroy-lobby-room', {
            room = room,
            newjid = room.jid,
            message = 'Host arrived.',
        });
    end
end

-- Events
module:hook('muc-occupant-pre-join', function(event)
    local room, occupant = event.room, event.occupant;

    if is_admin(occupant.bare_jid) or is_healthcheck_room(room.jid) or room._data.has_host then
        return;
    end

    -- FIXME: very unlikely race condition if callback executes before the following
    -- create-persistent-lobby-room event runs
    async_check_host(occupant, host_check_success)

    -- since theres no host let's enable lobby
    if not room:get_members_only() then
        module:log('info', 'Will wait for host in %s.', room.jid);
        prosody.events.fire_event('create-persistent-lobby-room', {
            room = room,
            reason = 'waiting-for-host',
            skip_display_name_check = true,
        });
    end
end);

module:hook('muc-occupant-left', function(event)
    local room, occupant, session = event.room, event.occupant, event.origin;

    if is_healthcheck_room(room.jid) or is_admin(occupant.bare_jid) then
        return;
    end

    if not session.is_valid_host or not has_non_system_occupant(room) or has_host(room) then
        return;
    end

    room._data.has_host = false;

    -- No other owners; try to promote, otherwise schedule destruction
    for _, o in room:each_occupant() do
        async_check_host(o, host_check_success)
    end

    -- if no host in 3 seconds, schedule room destruction
    -- FIXME: possible race condition with the async calls above
    timer.add_task(3, function()
        if not has_host(room) then
            schedule_room_destruction(room);
        end
    end);
end, -1); -- after persistent_lobby

process_host_module(lobby_muc_component_config, function(host_module, host)
    -- lobby muc component created
    module:log('info', 'Lobby component loaded %s', host);
    lobby_host = module:context(host_module);
end);
