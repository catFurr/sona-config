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
system_chat.send_to_participants(room, message, occupant.nick, "System");

-- Send private message to a single participant
system_chat.send_to_participant(room, message, [o1.nick, o2.nick], "System");
```
--]]

local st = require "util.stanza";
local json = require "cjson.safe";

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

    -- Send as a regular group chat body message so it shows up as normal chat
    local stanza = st.message({
        from = room.jid,
        type = "groupchat"
    });
    stanza:tag('nick', { xmlns = 'http://jabber.org/protocol/nick' }):text(displayName):up();
    stanza:tag('body'):text(message):up();

    module:log("debug", "Broadcasting group message (body) in room %s: %s", room.jid, message);

    room:broadcast_message(stanza);

    return true;
end

---
-- Send a private system message to a single participant
-- @param room The MUC room object
-- @param message The message text to send
-- @param occupantNick The full MUC JID (room@muc/nick) of the occupant to send to (bare JID also accepted)
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_participant(room, message, occupantNick, displayName)
    if not room or not message or not occupantNick then
        module:log("error", "Missing required parameters: room, message, and occupantNick");
        return false;
    end

    displayName = displayName or "System";

    -- Use json-message for private so UI can show custom displayName and treat it as private
    local data = {
        displayName = displayName,
        type = "system_chat_message",
        message = message,
    };

    local stanza = st.message({
        from = room.jid,
        type = "chat"
    });
    stanza.attr.to = occupantNick;
    stanza:tag('json-message', { xmlns = 'http://jitsi.org/jitmeet' }):text(json.encode(data)):up();

    module:log("debug", "Sending private system message to %s in room %s: %s", tostring(occupantNick),
        room.jid, message);

    room:route_stanza(stanza);
    return true;
end

---
-- Send a private system message to specific participants
-- @param room The MUC room object
-- @param message The message text to send
-- @param occupantNicks Array of participant full MUC JIDs (room@muc/nick) to send to (bare JIDs also accepted)
-- @param displayName Optional display name (defaults to "System")
-- @return boolean Success status
--
function SystemChat.send_to_participants(room, message, occupantNicks, displayName)
    if not room or not message or not occupantNicks then
        module:log("error", "Missing required parameters: room, message, and occupantNicks");
        return false;
    end

    if type(occupantNicks) ~= "table" then
        module:log("error", "occupantNicks must be an array/table");
        return false;
    end

    local success_count = 0;
    for _, to in ipairs(occupantNicks) do
        if SystemChat.send_to_participant(room, message, to, displayName) then
            success_count = success_count + 1;
        end
    end

    module:log("info", "Sent private system message to %d participants in room %s", success_count, room.jid);

    return success_count > 0;
end

module:log("info", "System chat utility module loaded");

return SystemChat;
