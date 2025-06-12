-- We need this for prosody 13.0
component_admins_as_room_owners = true

-- domain mapper options, must at least have domain base set to use the mapper
muc_mapper_domain_base = "meet.sonacove.com";

consider_bosh_secure = true;
https_ports = { }; -- prevent listening on port 5284
consider_websocket_secure = true;
cross_domain_websocket = true;
cross_domain_bosh = false;

-- by default prosody 0.12 sends cors headers, if you want to disable it uncomment the following (the config is available on 0.12.1)
--http_cors_override = {
--    bosh = {
--        enabled = false;
--    };
--    websocket = {
--        enabled = false;
--    };
--}

-- https://ssl-config.mozilla.org/#server=haproxy&version=2.1&config=intermediate&openssl=1.1.0g&guideline=5.4
ssl = {
    protocol = "tlsv1_2+";
    ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
}

unlimited_jids = {
    "focus@auth.meet.sonacove.com",
    "jvb@auth.meet.sonacove.com"
}

-- Cloudflare TURN configuration
cf_turn_app_id = "${CF_TURN_APP_ID}"
cf_turn_app_secret = "${CF_TURN_APP_SECRET}"

-- https://prosody.im/doc/modules/mod_smacks
smacks_max_unacked_stanzas = 5;
smacks_hibernation_time = 30;
smacks_max_old_sessions = 1;

VirtualHost "meet.sonacove.com"
    authentication = "token" -- do not delete me
    -- Properties below are modified by jitsi-meet-tokens package config
    -- and authentication above is switched to "token"
    app_id = "jitsi-meet"
    asap_key_server = true
    cache_keys_url = "https://auth.sonacove.com/realms/jitsi/protocol/openid-connect/certs"
    allow_empty_token = false
    asap_accepted_issuers = { "https://auth.sonacove.com/realms/jitsi" }
    asap_accepted_audiences = { "jitsi-web", "account" }
    asap_require_room_claim = true
    enable_domain_verification = false
    --app_secret="example_app_secret"
    -- Assign this host a certificate for TLS, otherwise it would use the one
    -- set in the global section (if any).
    -- Note that old-style SSL on port 5223 only supports one certificate, and will always
    -- use the global one.
    ssl = {
        key = "/config/certs/meet.sonacove.com.key";
        certificate = "/config/certs/meet.sonacove.com.crt";
    }
    av_moderation_component = "avmoderation.meet.sonacove.com"
    speakerstats_component = "speakerstats.meet.sonacove.com"
    end_conference_component = "endconference.meet.sonacove.com"
    modules_enabled = {
        "bosh";
        "websocket";
        "smacks";
        "ping"; -- Enable mod_ping
        "speakerstats";
        "external_services";
        "cf_turncredentials"; -- Support CF TURN/STUN
        --"meeting_host";

        "conference_duration";
        "end_conference";
        "muc_lobby_rooms";
        "muc_breakout_rooms";
        "av_moderation";
        "room_metadata";
    }
    c2s_require_encryption = false
    lobby_muc = "lobby.meet.sonacove.com"
    breakout_rooms_muc = "breakout.meet.sonacove.com"
    room_metadata_component = "metadata.meet.sonacove.com"
    main_muc = "conference.meet.sonacove.com"
    -- muc_lobby_whitelist = { "recorder.meet.sonacove.com" } -- Here we can whitelist jibri to enter lobby enabled rooms
    smacks_max_hibernated_sessions = 1

VirtualHost "guest.meet.sonacove.com"
    authentication = "anonymous"
    c2s_require_encryption = false

Component "conference.meet.sonacove.com" "muc"
    restrict_room_creation = true
    storage = "memory"
    modules_enabled = {
        "muc_hide_all";
        "muc_meeting_id";
        "muc_domain_mapper";
        "polls";
        "token_verification";
        "muc_rate_limit";
        "muc_password_whitelist";
    }
    admins = { "focus@auth.meet.sonacove.com" }
    muc_password_whitelist = {
        "focus@auth.meet.sonacove.com"
    }
    muc_room_locking = false
    muc_room_default_public_jids = true

Component "breakout.meet.sonacove.com" "muc"
    restrict_room_creation = true
    storage = "memory"
    modules_enabled = {
        "muc_hide_all";
        "muc_meeting_id";
        "muc_domain_mapper";
        "muc_rate_limit";
        "polls";
    }
    admins = { "focus@auth.meet.sonacove.com" }
    muc_room_locking = false
    muc_room_default_public_jids = true

-- internal muc component
Component "internal.auth.meet.sonacove.com" "muc"
    storage = "memory"
    modules_enabled = {
        "muc_hide_all";
        "ping";
    }
    admins = { "focus@auth.meet.sonacove.com", "jvb@auth.meet.sonacove.com" }
    muc_room_locking = false
    muc_room_default_public_jids = true

VirtualHost "auth.meet.sonacove.com"
    ssl = {
        key = "/config/certs/auth.meet.sonacove.com.key";
        certificate = "/config/certs/auth.meet.sonacove.com.crt";
    }
    modules_enabled = {
        "limits_exception";
        "smacks";
    }
    authentication = "internal_hashed"
    smacks_hibernation_time = 15;

VirtualHost "recorder.meet.sonacove.com"
    modules_enabled = {
      "smacks";
    }
    authentication = "internal_hashed"
    smacks_max_old_sessions = 2000;

-- Proxy to jicofo's user JID, so that it doesn't have to register as a component.
Component "focus.meet.sonacove.com" "client_proxy"
    target_address = "focus@auth.meet.sonacove.com"

Component "speakerstats.meet.sonacove.com" "speakerstats_component"
    muc_component = "conference.meet.sonacove.com"

Component "endconference.meet.sonacove.com" "end_conference"
    muc_component = "conference.meet.sonacove.com"

Component "avmoderation.meet.sonacove.com" "av_moderation_component"
    muc_component = "conference.meet.sonacove.com"

Component "lobby.meet.sonacove.com" "muc"
    storage = "memory"
    restrict_room_creation = true
    muc_room_locking = false
    muc_room_default_public_jids = true
    modules_enabled = {
        "muc_hide_all";
        "muc_rate_limit";
        "polls";
    }

Component "metadata.meet.sonacove.com" "room_metadata_component"
    muc_component = "conference.meet.sonacove.com"
    breakout_rooms_component = "breakout.meet.sonacove.com"
