module:log("info", "mod_firstowner loaded: will assign moderator to first room participant");

-- Test all possible MUC hooks to see which ones are triggered
local test_hooks = {
    "muc-room-created",
    "muc-room-pre-create", 
    "muc-room-destroyed",
    "muc-occupant-pre-join",
    "muc-occupant-about-to-join",
    "muc-occupant-joined",
    "muc-occupant-left",
    "muc-occupant-kicked",
    "muc-occupant-banned",
    "muc-occupant-affiliation-changed",
    "muc-occupant-role-changed",
    "muc-occupant-nick-changed",
    "muc-occupant-available",
    "muc-occupant-unavailable",
    "muc-occupant-presence",
    "muc-occupant-message",
    "muc-occupant-iq",
    "muc-occupant-subscription",
    "muc-occupant-subscribed",
    "muc-occupant-unsubscribe",
    "muc-occupant-unsubscribed"
}

-- Register test hooks for all possible MUC events
for _, hook_name in ipairs(test_hooks) do
    module:hook(hook_name, function(event)
        module:log("info", "mod_firstowner: %s hook triggered", hook_name);
        if event.room then
            module:log("info", "  Room: %s", event.room.jid or "<unknown>");
        end
        if event.occupant then
            module:log("info", "  Occupant: %s", event.occupant.bare_jid or "<unknown>");
        end
        if event.stanza then
            module:log("info", "  Stanza: %s", event.stanza.name or "<unknown>");
        end
    end);
end

-- Hook to detect when rooms are created
module:hook("muc-room-created", function(event)
    module:log("info", "mod_firstowner: muc-room-created hook triggered for room %s", event.room.jid or "<unknown>");
    event.room._first_owner_assigned = false;
end);

-- Hook to detect when rooms are being created
module:hook("muc-room-pre-create", function(event)
    module:log("info", "mod_firstowner: muc-room-pre-create hook triggered for room %s", event.room and event.room.jid or "<unknown>");
end);

-- Hook to detect when rooms are being destroyed
module:hook("muc-room-destroyed", function(event)
    module:log("info", "mod_firstowner: muc-room-destroyed hook triggered for room %s", event.room and event.room.jid or "<unknown>");
end);

-- Hook to detect when users are about to join (earlier in the process)
module:hook("pre-presence", function(event)
    if event.stanza and event.stanza.attr.type == "subscribe" then
        module:log("info", "mod_firstowner: User attempting to subscribe to room");
    end
end);

-- Main hook for occupant joining - use very high priority to run before token_verification
module:hook("muc-occupant-pre-join", function(event)
    module:log("info", "mod_firstowner: muc-occupant-pre-join hook triggered");
    local room = event.room;
    local occupant_jid = event.stanza and event.stanza.attr.from;
    
    if not occupant_jid then
        module:log("warn", "No occupant JID found during muc-occupant-pre-join for room %s", room.jid or "<unknown>");
        return;
    end

    module:log("debug", "User %s is attempting to join room %s", occupant_jid, room.jid or "<unknown>");

    -- Check if we've already assigned a first owner
    if not room._first_owner_assigned then
        room:set_affiliation(true, occupant_jid, "owner");
        room._first_owner_assigned = true;
        module:log("info", "Set %s as first owner in room %s", occupant_jid, room.jid or "<unknown>");
    else
        module:log("debug", "Room %s already has a first owner. Skipping owner assignment for %s", room.jid or "<unknown>", occupant_jid);
    end
end, 200); -- Very high priority to run before token_verification

-- Hook for when users are about to be added to the room
module:hook("muc-occupant-about-to-join", function(event)
    module:log("info", "mod_firstowner: muc-occupant-about-to-join hook triggered");
    local room = event.room;
    local occupant_jid = event.occupant and event.occupant.bare_jid;
    
    if not occupant_jid then
        module:log("warn", "No occupant JID found during muc-occupant-about-to-join for room %s", room.jid or "<unknown>");
        return;
    end

    module:log("debug", "User %s is about to join room %s", occupant_jid, room.jid or "<unknown>");

    -- Check if we've already assigned a first owner
    if not room._first_owner_assigned then
        room:set_affiliation(true, occupant_jid, "owner");
        room._first_owner_assigned = true;
        module:log("info", "Set %s as first owner in room %s", occupant_jid, room.jid or "<unknown>");
    else
        module:log("debug", "Room %s already has a first owner. Skipping owner assignment for %s", room.jid or "<unknown>", occupant_jid);
    end
end, 200);

-- Hook to detect when users have joined
module:hook("muc-occupant-joined", function(event)
    module:log("info", "mod_firstowner: muc-occupant-joined hook triggered");
    local room = event.room;
    local occupant = event.occupant;
    local occupant_jid = occupant and occupant.bare_jid;
    
    if not occupant_jid then
        module:log("warn", "No occupant JID found during muc-occupant-joined for room %s", room.jid or "<unknown>");
        return;
    end

    module:log("debug", "User %s joined room %s", occupant_jid, room.jid or "<unknown>");
    
    -- Log the current affiliation of this user
    local current_aff = room:get_affiliation(occupant_jid);
    module:log("info", "User %s has affiliation: %s", occupant_jid, current_aff or "none");
    
    -- Log all affiliations in the room
    module:log("info", "All affiliations in room %s:", room.jid or "<unknown>");
    for jid, aff in pairs(room._affiliations or {}) do
        module:log("info", "  %s → %s", jid, aff);
    end
end);

-- Hook to prevent token_verification from overriding our owner assignment
module:hook("muc-occupant-pre-join", function(event)
    local room = event.room;
    local occupant_jid = event.stanza and event.stanza.attr.from;
    
    if not occupant_jid then
        return;
    end

    -- Check if this user is already an owner (set by our plugin)
    local current_aff = room:get_affiliation(occupant_jid);
    if current_aff == "owner" then
        module:log("info", "mod_firstowner: Preventing token_verification from overriding owner status for %s", occupant_jid);
        -- We could potentially modify the event here to prevent further processing
    end
end, 250); -- Run after our main hook but before token_verification
