--[[
System Chat Message Module for Sonacove (Utility/Dependency Module)

This module provides functionality for sending system chat messages to meeting participants.
It can send messages to all participants in a room or private messages to specific participants.
This module is designed to be used as a dependency by other modules rather than being loaded
directly in the Prosody configuration.

## Usage

```lua
local system_chat = module:require "custom/mod_system_chat";

-- Send message to all participants in a room (group chat)
system_chat.send_to_all(room, message, "System");

-- Send private message to specific participants
system_chat.send_to_participants(room, message, [o1, o2], "System");

-- Send private message to a single participant
system_chat.send_to_participant(room, message, occupant, "System");
```
--]]

local st = require "util.stanza";
local json = require "cjson.safe";


local function get_jid_from_occupant(occupant)
    if not occupant or not occupant.bare_jid then
        module:log("error", "Invalid occupant or missing bare_jid");
        return nil;
    end

    if occupant.jid then return occupant.jid end

    -- We get the resource from the active session
    local _user = prosody.bare_sessions[occupant.bare_jid];
    if _user and _user.sessions then
        for resource, _s in pairs(_user.sessions) do
            -- TODO warn if more than one session found
            if _s then

                if _s.full_jid then return _s.full_jid end

                if _s.resource then
                    return occupant.bare_jid .. "/" .. _s.resource
                end

                return occupant.bare_jid .. "/" .. resource
            end
        end
    end
end

local SystemChat = {};

function SystemChat.format_seconds(num_seconds)
    local minutes = math.floor(num_seconds / 60);
    local seconds = num_seconds % 60;
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

    return time_message
end

---
-- Send a private system message to a single participant
-- @param room The MUC room object
-- @param message The message text to send
-- @param occupant The occupant object to send to
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_participant(room, message, occupant, displayName)
    if not room or not message or not occupant then
        module:log("error", "Missing required parameters: room, message, and occupant");
        return false;
    end

    local occJID = get_jid_from_occupant(occupant);
    if not occJID then return false end

    -- Use json-message for private so UI can show custom displayName and treat it as private
    local data = { type = "system_chat_message", message = message, displayName = displayName };
    local stanza = st.message({ from = room.jid, type = "chat" });
    stanza.attr.to = occJID;

    stanza:tag('json-message', { xmlns = 'http://jitsi.org/jitmeet' }):text(json.encode(data)):up();

    module:log("debug", "Sending private system message to %s in room %s: %s", tostring(occJID), room.jid, message);

    room:route_stanza(stanza);
    return true;
end

---
-- Send a private system message to specific participants
-- @param room The MUC room object
-- @param message The message text to send
-- @param occupants Array of occupant objects to send to
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_participants(room, message, occupants, displayName)
    if not room or not message or not occupants then
        module:log("error", "Missing required parameters: room, message, and occupants");
        return false;
    end

    if type(occupants) ~= "table" then
        module:log("error", "occupants must be an array/table");
        return false;
    end

    local success_count = 0;
    for _, occupant in ipairs(occupants) do
        if SystemChat.send_to_participant(room, message, occupant, displayName) then
            success_count = success_count + 1;
        end
    end

    -- module:log("info", "Sent private system message to %d participants in room %s", success_count, room.jid);

    return success_count > 0;
end

---
-- Send a system message to all participants in a room (group chat)
-- @param room The MUC room object
-- @param message The message text to send
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_all(room, message, displayName)
    if not room or not message then
        module:log("error", "Missing required parameters: room and message");
        return false;
    end

    -- Collect occupants into a table first since room:each_occupant() returns an iterator function
    local occupants = {};
    for occupant in room:each_occupant() do
        table.insert(occupants, occupant);
    end

    -- module:log("debug", "Broadcasting group message (body) in room %s: %s", room.jid, message);

    return SystemChat.send_to_participants(room, message, occupants, displayName)
end

module:log("info", "System chat utility module loaded");

return SystemChat;
