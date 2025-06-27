-- Plugin to validate user's subscription status from JWT claims


module:hook("jitsi-authentication-token-verified", function(event)
    local session = event.session;
    local claims = event.claims;

    module:log("debug", "Checking subscription status for session %s", tostring(session.id));

    local context = claims["context"];
    if not context then
        module:log("warn", "JWT token missing 'context' claim");
        session:close();
        return true;
    end

    local user = context["user"];
    if not user then
        module:log("warn", "JWT token missing 'user' object in context");
        session:close();
        return true;
    end

    local status = user["subscription_status"];
    module:log("debug", "User subscription_status: %s", tostring(status));

    if status ~= "active" and status ~= "trialing" then
        module:log("warn", "Rejected token: subscription_status is '%s'", tostring(status));
        session:close();
        return true; -- stop further processing
    end

    module:log("debug", "Subscription status is valid: %s", status);
end, 50);
