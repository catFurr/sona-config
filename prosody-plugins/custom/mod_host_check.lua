--[[
Host Check Module for Sonacove MUC

This module provides host validation functionality for meeting participants.
]]

local jid = require 'util.jid';
local timer = require 'util.timer';

local util = module:require "util";
local is_admin = util.is_admin;
local is_healthcheck_room = util.is_healthcheck_room;


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
local function async_check_host(occupant, callback)
    local bare_jid = occupant.bare_jid;
    local room = occupant.room;
    local domain = jid.host(bare_jid);
    local username = jid.node(bare_jid);

    if is_admin(occupant.bare_jid) or not room or is_healthcheck_room(room.jid) or room._data.has_host then
        -- we dont need to call the api if there's already a host
        return;
    end

    local user_sessions = prosody.hosts[domain] and prosody.hosts[domain].sessions;
    local user_session = user_sessions and user_sessions[username];
    if not user_session then
        return;
    end

    -- Find the first available session for this user
    local session;
    for resource, sess in pairs(user_session.sessions) do
        if sess then
            session = sess;
            break;
        end
    end

    if not session or not is_subbed_user(session) then
        return;
    end

    -- Check if this session is already validated as a host
    if session.is_valid_host then
        callback({ room = room, occupant = occupant, session = session });
        return;
    end

    -- Call the http endpoint asynchronously
    -- TODO: for now we simulate the call with a timer.
    timer.add_task(1, function()
        if true then
            session.is_valid_host = true;
            callback({ room = room, occupant = occupant, session = session });
        end
    end);
end

-- Export the function for other modules to use
module:export('async_check_host', async_check_host);
