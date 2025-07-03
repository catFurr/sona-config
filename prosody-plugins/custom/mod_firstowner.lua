module:log("info", "mod_firstowner loaded: will assign moderator to first room participant");

-- Hook into the 'muc-occupant-pre-join' event, which is triggered just before a user joins a MUC room.
module:hook("muc-occupant-pre-join", function(event)
    local room = event.room;
    local occupant_jid = event.stanza.attr.from;
    module:log("info", "mod_firstowner plugin running")

    -- If we can't determine the user's JID, log a warning and exit early
    if not occupant_jid then
        module:log("warn", "No occupant JID found during muc-occupant-pre-join for room %s", room.jid or "<unknown>");
        return;
    end

    module:log("debug", "User %s is attempting to join room %s", occupant_jid, room.jid or "<unknown>");

    -- Check if the room already has an owner
    local has_owner = false;
    for jid, aff in pairs(room._affiliations or {}) do
        module:log("debug", "Affiliation check: %s → %s", jid, aff);
        if aff == "owner" then
            has_owner = true;
            break;
        end
    end

    -- If there is no owner, set the joining user as the owner
    if not has_owner then
        room:set_affiliation(true, occupant_jid, "owner");
        module:log("info", "Set %s as first owner in room %s", occupant_jid, room.jid or "<unknown>");
    else
        -- If there is already an owner, do nothing
        module:log("debug", "Room %s already has an owner. Skipping owner assignment for %s", room.jid or "<unknown>", occupant_jid);
    end
end, 100); -- Priority 150 to run before some other modules
