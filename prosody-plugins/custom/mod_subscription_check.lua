
--[[
Subscriber Check for Sonacove

Ensures user is an active or trialing subsriber.

Configuration:
- Module should be enabled under the main virtual host:
  VirtualHost "${XMPP_DOMAIN}"
      modules_enabled = {
          ...
          "subscription_check";
      }

]]

local util = module:require 'util';
local is_admin = util.is_admin;
local is_healthcheck_room = util.is_healthcheck_room;
local ends_with = util.ends_with;


-- Helpers
local function is_focus_occupant(occupant)
    return occupant and occupant.nick and ends_with(occupant.nick, '/focus');
end

-- Gate room creation with subscription check only
module:hook('post-jitsi-authentication', function (event)
    local room, occupant, session, stanza, origin = event.room, event.occupant, event.origin, event.stanza, event.origin;

    if is_healthcheck_room(room.jid) or is_admin(occupant.bare_jid) or is_focus_occupant(occupant) then
        return;
    end

    -- Are we the first non-system occupant? (room creation)
    for _, o in room:each_occupant() do
        if o ~= occupant and not is_admin(o.bare_jid) and not is_focus_occupant(o) then
            module:log('info', 'Room %s already has occupants, skipping subscription check', room.jid);
            return;
        end
    end

    -- Subscription check (active or trialing)
    local ctx_user = session and session.jitsi_meet_context_user;
    local sub_status = ctx_user and ctx_user.subscription_status;

    module:log('info', 'Checking subscription for room creation: user=%s, sub_status=%s', 
               ctx_user and ctx_user.id or 'nil', sub_status or 'nil');

    if not (sub_status == 'active' or sub_status == 'trialing') then
        return false, 'subscription-required';
    end

    -- Mark creator for tracing
    room._data.meeting_host_first_bare_jid = room._data.meeting_host_first_bare_jid or occupant.bare_jid;
end);

