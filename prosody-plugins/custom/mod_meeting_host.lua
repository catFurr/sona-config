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
local jid = require 'util.jid';

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

local function is_subbed_user(session)
    -- Get user context from session
    local ctx_user = session and session.jitsi_meet_context_user;
    local sub_status = ctx_user and ctx_user.subscription_status;

    if sub_status == 'active' or sub_status == 'trialing' then
        return true;
    end
    return false;
end

-- callback expects arg: { room, occupant, session }
local function async_check_host(occupant, room, callback)
    -- occupant.sessions = table: 0x594eb79b0ce0
    -- occupant.bare_jid = df4b3628-e17e-4a15-9719-59811caec24e@guest.staj.sonacove.com
    -- occupant.nick = poo@conference.staj.sonacove.com/df4b3628
    -- occupant.stable_id = rYfYHMPUCD80nZBbf1wa4gk+oygYqBcWm0casoeh9Gg=
    -- occupant.role = participant

    -- _rr.speakerStats = table: 0x594eb766a130
    -- _rr.sent_initial_metadata = table: 0x594eb766a1d0
    -- _rr._affiliation_data = table: 0x594eb7d23300
    -- _rr.jitsiMetadata = table: 0x594eb766a190
    -- _rr._occupants = table: 0x594eb7d23240
    -- _rr._data = table: 0x594eb7d23280
    -- _rr.send_default_permissions_to = table: 0x594eb6c77cd0
    -- _rr.save = function @mod_muc.lua:155(room, forced, savestate)
    -- _rr.polls = table: 0x594eb766a000
    -- _rr._reserved_nicks = table: 0x594eb6a3bc00
    -- _rr.jid = poo@conference.staj.sonacove.com
    -- _rr._jid_nick = table: 0x594eb7d23200
    -- _rr._affiliations = table: 0x594eb7d232c0
    -- _rr.join_rate_throttle = table: 0x594eb6c78850

    if not occupant or not room then return end

    if is_admin(occupant.bare_jid) or is_healthcheck_room(room.jid) or room._data.has_host then
        -- we dont need to call the api if there's already a host
        module:log('info', 'is_admin? %s, is_room? %s, is_health? %s, has_host? %s',
            is_admin(occupant.bare_jid), not room, is_healthcheck_room(room.jid), room._data.has_host);

        return;
    end

    module:log('info', 'check host; room passed check');

    local session;
    local _user = prosody.bare_sessions[occupant.bare_jid];
    if _user and _user.sessions then
        for resource, _s in pairs(_user.sessions) do
            if _s then
                session = _s;
                break;
            end
        end
    end

    module:log('info', 'check host; valid session found.');

    if not session or not is_subbed_user(session) then return end

    -- Check if this session is already validated as a host
    if session.is_valid_host then
        callback({ room = room, occupant = occupant, session = session });
        return;
    end

    -- Call the http endpoint asynchronously
    -- TODO: for now we simulate the call with a timer.
    timer.add_task(1, function()
        session.is_valid_host = true;
        callback({ room = room, occupant = occupant, session = session });
    end);
end

local function schedule_room_destruction(room)
    if not room or is_healthcheck_room(room.jid) then return end

    -- If a destruction is already scheduled, don't schedule another
    if room._data.meeting_host_destroy_at then return end

    room._data.meeting_host_destroy_at = socket.gettime() + destroy_delay_seconds;
    local target_room_jid = room.jid;

    module:log('info', 'Scheduling room destruction for %s in %ds', target_room_jid, destroy_delay_seconds);

    -- Notify all participants that the meeting will end soon
    local time_message = system_chat.format_seconds(destroy_delay_seconds);

    local warning_message = string.format(
        "⚠️ This meeting will end in %s due to no Host being present. " ..
        "Host can rejoin to prevent this from happening.",
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
        prosody.events.fire_event('maybe-destroy-room', {
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
    if not room._data or room._data.has_host then return end

    room._data.has_host = true;

    room:set_affiliation(true, occupant.bare_jid, 'owner');
    occupant.role = room:get_default_role(room:get_affiliation(occupant.bare_jid)) or 'moderator';

    module:log('info', 'host check success');

    -- Send private message to the new host about whiteboard functionality
    system_chat.send_to_participant(room,
        "You are the meeting host. Please use excalidraw.com for whiteboard functionality.",
        occupant.nick,
        "System");

    -- Cancel any scheduled destruction on join
    if room._data.meeting_host_destroy_at then
        room._data.meeting_host_destroy_at = nil;
        module:log('info', 'Cancelled scheduled room destruction for %s (participant joined)', room.jid);

        system_chat.send_to_all(room,
            "✅ The meeting has a new Host. The automatic room close has been cancelled.",
            "System");
    end

    if has_non_system_occupant(room) then
        -- we are in the room already
        -- We are in an existing meeting. don't change the lobby settings.
    elseif room:get_members_only() then
        -- Empty room, let's bring everyone in and destroy the lobby
        room:set_members_only(false);
        room._data.persist_lobby = false;

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

    -- once the meeting starts lets not manage the lobby anymore, avoids some edge cases
    if has_non_system_occupant(room) then
        return;
    end

    module:log('info', 'occ pre join; jid? %s', occupant.bare_jid);

    -- FIXME: very unlikely race condition if callback executes before the following
    -- create-persistent-lobby-room event runs
    async_check_host(occupant, room, host_check_success)

    module:log('info', 'post fire check host');

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

    module:log('info', 'occ left; is valid host? %s', session.is_valid_host);

    if not session.is_valid_host or not has_non_system_occupant(room) or has_host(room) then
        return;
    end

    room._data.has_host = false;

    -- No other owners; try to promote, otherwise schedule destruction
    for _, o in room:each_occupant() do
        if o.role == 'moderator' then
            async_check_host(o, room, host_check_success)
        end
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
