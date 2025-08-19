--[[
System Chat Message Module for Sonacove (Utility/Dependency Module)

This module provides functionality for sending system chat messages to meeting participants.
It can send messages to all participants in a room or private messages to specific participants.
This module is designed to be used as a dependency by other modules rather than being loaded
directly in the Prosody configuration.

## Usage

```lua
local system_chat = module:require "custom/mod_system_chat";

-- Send message to all participants in a room (group chat):
system_chat.send_to_all(room, message, displayName)

-- Send private message to specific participants:
system_chat.send_to_participants(room, message, occupantJIDs, displayName)

-- Send private message to a single participant:
system_chat.send_to_participant(room, message, occupantJID, displayName)
```

## Parameters

- `room`: The MUC room object
- `message`: The text message to send (string)
- `displayName`: Optional display name for the system sender (string, defaults to "System")
- `connectionJIDs`: Array of participant JIDs to send private messages to
- `participantJID`: Single participant JID for private message

## Message Format

Messages are sent as JSON-message stanzas with the following structure:
```json
{
  "displayName": "System",
  "type": "system_chat_message",
  "message": "Your message here"
}
```
--]]

local st = require "util.stanza";
local json = require "cjson.safe";

local util = module:require "util";
local is_admin = util.is_admin;
local ends_with = util.ends_with;

local SystemChat = {};

-- Local utility function to create JSON message stanza
local function create_json_message_stanza(from, to, message_data, message_type)
    local stanza = st.message({
        from = from,
        type = message_type
    });

    if to then
        stanza.attr.to = to;
    end

    return stanza:tag('json-message', { xmlns = 'http://jitsi.org/jitmeet' })
        :text(json.encode(message_data))
        :up();
end

-- Local utility function to check if occupant should receive messages
local function should_message_occupant(occupant)
    return occupant.bare_jid and
        not is_admin(occupant.bare_jid) and
        not (occupant.nick and ends_with(occupant.nick, '/focus'));
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

    displayName = displayName or "System";

    local data = {
        displayName = displayName,
        type = "system_chat_message",
        message = message,
    };

    local stanza = create_json_message_stanza(room.jid, nil, data, "groupchat");

    module:log("debug", "Sending system message to all participants in room %s: %s", room.jid, message);

    -- Broadcast to all occupants
    room:broadcast_message(stanza);

    return true;
end

---
-- Send a private system message to a single participant
-- @param room The MUC room object
-- @param message The message text to send
-- @param occupantJID The JID of the occupant to send to
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_participant(room, message, occupantJID, displayName)
    if not room or not message or not occupantJID then
        module:log("error", "Missing required parameters: room, message, and occupantJID");
        return false;
    end

    displayName = displayName or "System";

    local data = {
        displayName = displayName,
        type = "system_chat_message",
        message = message,
    };

    local stanza = create_json_message_stanza(room.jid, occupantJID, data, "chat");

    module:log("debug", "Sending private system message to %s in room %s: %s", occupantJID, room.jid, message);

    room:route_stanza(stanza);
    return true;
end

---
-- Send a private system message to specific participants
-- @param room The MUC room object
-- @param message The message text to send
-- @param occupantJIDs Array of occupant JIDs to send to
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_participants(room, message, occupantJIDs, displayName)
    if not room or not message or not occupantJIDs then
        module:log("error", "Missing required parameters: room, message, and occupantJIDs");
        return false;
    end

    if type(occupantJIDs) ~= "table" then
        module:log("error", "occupantJIDs must be an array/table");
        return false;
    end

    local success_count = 0;

    for _, to in ipairs(occupantJIDs) do
        if to and to ~= "" then
            if SystemChat.send_to_participant(room, message, to, displayName) then
                success_count = success_count + 1;
            end
        else
            module:log("warn", "Skipping empty or nil JID in occupantJIDs");
        end
    end

    module:log("info", "Sent private system message to %d participants in room %s", success_count, room.jid);

    return success_count > 0;
end

module:log("info", "System chat utility module loaded");

return SystemChat;
