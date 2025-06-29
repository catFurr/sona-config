module:log("info", "mod_firstowner loaded: will assign moderator to first room participant");

-- Test if module is properly loaded
module:hook("module-loaded", function(event)
    module:log("info", "mod_firstowner: module-loaded hook triggered for module: %s", event.module or "unknown");
end);

-- Test if the module is being initialized
module:hook("module-initialized", function(event)
    module:log("info", "mod_firstowner: module-initialized hook triggered for module: %s", event.module or "unknown");
end);

-- Test if presence events are being processed
module:hook("pre-presence", function(event)
    module:log("info", "mod_firstowner: pre-presence hook triggered");
    if event.stanza then
        module:log("info", "mod_firstowner: presence stanza type: %s", event.stanza.attr.type or "none");
    end
end);

-- Test if message events are being processed
module:hook("pre-message", function(event)
    if event.stanza and event.stanza.name == "presence" then
        module:log("info", "mod_firstowner: pre-message hook triggered for presence");
    end
end);

-- Hook to detect when rooms are created
module:hook("muc-room-created", function(event)
    module:log("info", "mod_firstowner: muc-room-created hook triggered for room %s", event.room.jid or "<unknown>");
    
    -- Store a flag in the room to track if we've assigned an owner
    event.room._first_owner_assigned = false;
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
