module:log("info", "mod_firstowner loaded: will assign moderator to first room participant");

module:hook("muc-occupant-pre-join", function(event)
    local room = event.room;
    local occupant_jid = event.stanza.attr.from;
    module:log("info", "mod_firstowner plugin running")

    if not occupant_jid then
        module:log("warn", "No occupant JID found during muc-occupant-pre-join for room %s", room.jid or "<unknown>");
        return;
    end

    module:log("debug", "User %s is attempting to join room %s", occupant_jid, room.jid or "<unknown>");

    local has_owner = false;
    for jid, aff in pairs(room._affiliations or {}) do
        module:log("debug", "Affiliation check: %s → %s", jid, aff);
        if aff == "owner" then
            has_owner = true;
            break;
        end
    end

    if not has_owner then
        room:set_affiliation(true, occupant_jid, "owner");
        module:log("info", "Set %s as first owner in room %s", occupant_jid, room.jid or "<unknown>");
    else
        module:log("debug", "Room %s already has an owner. Skipping owner assignment for %s", room.jid or "<unknown>", occupant_jid);
    end
end, 150);
