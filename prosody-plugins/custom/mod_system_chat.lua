--[[
System Chat Message Module for Sonacove (Utility/Dependency Module)

This module provides functionality for sending system chat messages to meeting participants.
It can send messages to all participants in a room or private messages to specific participants.
This module is designed to be used as a dependency by other modules rather than being loaded
directly in the Prosody configuration.

## Usage

```lua
local system_chat = module:require "custom/mod_system_chat";

-- Send message to all participants in a room:
system_chat.send_to_all(room, message, displayName)

-- Send private message to specific participants:
system_chat.send_to_participants(room, message, connectionJIDs, displayName)

-- Send private message to a single participant:
system_chat.send_to_participant(room, message, participantJID, displayName)
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
local get_room_from_jid = util.get_room_from_jid;

local SystemChat = {};

---
-- Send a system message to all participants in a room
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

    local stanza = st.message({
        from = room.jid,
        type = "groupchat"
    })
    :tag('json-message', { xmlns = 'http://jitsi.org/jitmeet' })
    :text(json.encode(data))
    :up();

    module:log("debug", "Sending system message to all participants in room %s: %s", room.jid, message);
    
    -- Broadcast to all occupants
    room:broadcast_message(stanza);
    
    return true;
end

---
-- Send a private system message to specific participants
-- @param room The MUC room object
-- @param message The message text to send
-- @param connectionJIDs Array of participant JIDs to send to
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_participants(room, message, connectionJIDs, displayName)
    if not room or not message or not connectionJIDs then
        module:log("error", "Missing required parameters: room, message, and connectionJIDs");
        return false;
    end

    if type(connectionJIDs) ~= "table" then
        module:log("error", "connectionJIDs must be an array/table");
        return false;
    end

    displayName = displayName or "System";

    local data = {
        displayName = displayName,
        type = "system_chat_message",
        message = message,
    };

    local success_count = 0;
    
    for _, to in ipairs(connectionJIDs) do
        if to and to ~= "" then
            local stanza = st.message({
                from = room.jid,
                to = to,
                type = "chat"
            })
            :tag('json-message', { xmlns = 'http://jitsi.org/jitmeet' })
            :text(json.encode(data))
            :up();

            module:log("debug", "Sending private system message to %s in room %s: %s", to, room.jid, message);
            
            room:route_stanza(stanza);
            success_count = success_count + 1;
        else
            module:log("warn", "Skipping empty or nil JID in connectionJIDs");
        end
    end

    module:log("info", "Sent private system message to %d participants in room %s", success_count, room.jid);
    
    return success_count > 0;
end

---
-- Send a private system message to a single participant
-- @param room The MUC room object
-- @param message The message text to send
-- @param participantJID The JID of the participant to send to
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_participant(room, message, participantJID, displayName)
    if not room or not message or not participantJID then
        module:log("error", "Missing required parameters: room, message, and participantJID");
        return false;
    end

    return SystemChat.send_to_participants(room, message, { participantJID }, displayName);
end

---
-- Helper function to get a room by JID and send message to all participants
-- @param roomJID The JID of the room
-- @param message The message text to send
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_all_by_jid(roomJID, message, displayName)
    if not roomJID or not message then
        module:log("error", "Missing required parameters: roomJID and message");
        return false;
    end

    local room = get_room_from_jid(roomJID);
    if not room then
        module:log("error", "Room not found: %s", roomJID);
        return false;
    end

    return SystemChat.send_to_all(room, message, displayName);
end

---
-- Helper function to get a room by JID and send private messages to specific participants
-- @param roomJID The JID of the room
-- @param message The message text to send
-- @param connectionJIDs Array of participant JIDs to send to
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_participants_by_jid(roomJID, message, connectionJIDs, displayName)
    if not roomJID or not message or not connectionJIDs then
        module:log("error", "Missing required parameters: roomJID, message, and connectionJIDs");
        return false;
    end

    local room = get_room_from_jid(roomJID);
    if not room then
        module:log("error", "Room not found: %s", roomJID);
        return false;
    end

    return SystemChat.send_to_participants(room, message, connectionJIDs, displayName);
end

---
-- Get all participant JIDs in a room (excluding admin/focus occupants)
-- @param room The MUC room object
-- @return table Array of participant JIDs
--
function SystemChat.get_participant_jids(room)
    if not room then
        module:log("error", "Room parameter is required");
        return {};
    end

    local jids = {};
    local is_admin = util.is_admin;
    local ends_with = util.ends_with;
    
    for _, occupant in room:each_occupant() do
        -- Skip admin users and focus (jitsi-meet component)
        if occupant.bare_jid and 
           not is_admin(occupant.bare_jid) and 
           not (occupant.nick and ends_with(occupant.nick, '/focus')) then
            table.insert(jids, occupant.jid);
        end
    end
    
    return jids;
end

---
-- Send a system message to all non-admin participants in a room
-- @param room The MUC room object
-- @param message The message text to send
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_all_participants(room, message, displayName)
    if not room or not message then
        module:log("error", "Missing required parameters: room and message");
        return false;
    end

    local participant_jids = SystemChat.get_participant_jids(room);
    
    if #participant_jids == 0 then
        module:log("info", "No participants found in room %s", room.jid);
        return true; -- Not an error, just no participants
    end

    return SystemChat.send_to_participants(room, message, participant_jids, displayName);
end

module:log("info", "System chat utility module loaded");

return SystemChat;
