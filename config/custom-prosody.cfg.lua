-- We need this for prosody 13.0
component_admins_as_room_owners = true

-- domain mapper options, must at least have domain base set to use the mapper
muc_mapper_domain_base = "{{ .Env.XMPP_DOMAIN }}";

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
    "focus@{{ .Env.XMPP_AUTH_DOMAIN }}",
    "jvb@{{ .Env.XMPP_AUTH_DOMAIN }}"
}

-- Cloudflare TURN configuration
cf_turn_app_id = "{{ .Env.CF_TURN_APP_ID }}"
cf_turn_app_secret = "{{ .Env.CF_TURN_APP_SECRET }}"

-- https://prosody.im/doc/modules/mod_smacks
smacks_max_unacked_stanzas = 5;
smacks_hibernation_time = 30;
smacks_max_old_sessions = 1;

VirtualHost "{{ .Env.XMPP_DOMAIN }}"
    authentication = "token" -- do not delete me
    -- Properties below are modified by jitsi-meet-tokens package config
    -- and authentication above is switched to "token"
    app_id = "jitsi-meet"
    asap_key_server = true
    cache_keys_url = "{{ .Env.KC_HOST_URL }}realms/jitsi/protocol/openid-connect/certs"
    asap_accepted_issuers = { "{{ .Env.KC_HOST_URL }}realms/jitsi" }
    asap_accepted_audiences = { "jitsi-web", "account" }
    allow_empty_token = false
    asap_require_room_claim = true
    enable_domain_verification = false
    --app_secret="example_app_secret"
    -- Assign this host a certificate for TLS, otherwise it would use the one
    -- set in the global section (if any).
    -- Note that old-style SSL on port 5223 only supports one certificate, and will always
    -- use the global one.
    ssl = {
        key = "/config/certs/{{ .Env.XMPP_DOMAIN }}.key";
        certificate = "/config/certs/{{ .Env.XMPP_DOMAIN }}.crt";
    }
    av_moderation_component = "avmoderation.{{ .Env.XMPP_DOMAIN }}"
    speakerstats_component = "speakerstats.{{ .Env.XMPP_DOMAIN }}"
    end_conference_component = "endconference.{{ .Env.XMPP_DOMAIN }}"
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
    lobby_muc = "lobby.{{ .Env.XMPP_DOMAIN }}"
    breakout_rooms_muc = "breakout.{{ .Env.XMPP_DOMAIN }}"
    room_metadata_component = "metadata.{{ .Env.XMPP_DOMAIN }}"
    main_muc = "{{ .Env.XMPP_MUC_DOMAIN }}"
    -- muc_lobby_whitelist = { "{{ .Env.XMPP_HIDDEN_DOMAIN }}" } -- Here we can whitelist jibri to enter lobby enabled rooms
    smacks_max_hibernated_sessions = 1

VirtualHost "guest.{{ .Env.XMPP_DOMAIN }}"
    authentication = "anonymous"
    c2s_require_encryption = false

Component "{{ .Env.XMPP_MUC_DOMAIN }}" "muc"
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
    admins = { "focus@{{ .Env.XMPP_AUTH_DOMAIN }}" }
    muc_password_whitelist = {
        "focus@{{ .Env.XMPP_AUTH_DOMAIN }}"
    }
    muc_room_locking = false
    muc_room_default_public_jids = true

Component "breakout.{{ .Env.XMPP_DOMAIN }}" "muc"
    restrict_room_creation = true
    storage = "memory"
    modules_enabled = {
        "muc_hide_all";
        "muc_meeting_id";
        "muc_domain_mapper";
        "muc_rate_limit";
        "polls";
    }
    admins = { "focus@{{ .Env.XMPP_AUTH_DOMAIN }}" }
    muc_room_locking = false
    muc_room_default_public_jids = true

-- internal muc component
Component "{{ .Env.XMPP_INTERNAL_MUC_DOMAIN }}" "muc"
    storage = "memory"
    modules_enabled = {
        "muc_hide_all";
        "ping";
    }
    admins = { "focus@{{ .Env.XMPP_AUTH_DOMAIN }}", "jvb@{{ .Env.XMPP_AUTH_DOMAIN }}" }
    muc_room_locking = false
    muc_room_default_public_jids = true

VirtualHost "{{ .Env.XMPP_AUTH_DOMAIN }}"
    ssl = {
        key = "/config/certs/{{ .Env.XMPP_AUTH_DOMAIN }}.key";
        certificate = "/config/certs/{{ .Env.XMPP_AUTH_DOMAIN }}.crt";
    }
    modules_enabled = {
        "limits_exception";
        "smacks";
    }
    authentication = "internal_hashed"
    smacks_hibernation_time = 15;

VirtualHost "{{ .Env.XMPP_HIDDEN_DOMAIN }}"
    modules_enabled = {
      "smacks";
    }
    authentication = "internal_hashed"
    smacks_max_old_sessions = 2000;

-- Proxy to jicofo's user JID, so that it doesn't have to register as a component.
Component "focus.{{ .Env.XMPP_DOMAIN }}" "client_proxy"
    target_address = "focus@{{ .Env.XMPP_AUTH_DOMAIN }}"

Component "speakerstats.{{ .Env.XMPP_DOMAIN }}" "speakerstats_component"
    muc_component = "{{ .Env.XMPP_MUC_DOMAIN }}"

Component "endconference.{{ .Env.XMPP_DOMAIN }}" "end_conference"
    muc_component = "{{ .Env.XMPP_MUC_DOMAIN }}"

Component "avmoderation.{{ .Env.XMPP_DOMAIN }}" "av_moderation_component"
    muc_component = "{{ .Env.XMPP_MUC_DOMAIN }}"

Component "lobby.{{ .Env.XMPP_DOMAIN }}" "muc"
    storage = "memory"
    restrict_room_creation = true
    muc_room_locking = false
    muc_room_default_public_jids = true
    modules_enabled = {
        "muc_hide_all";
        "muc_rate_limit";
        "polls";
    }

Component "metadata.{{ .Env.XMPP_DOMAIN }}" "room_metadata_component"
    muc_component = "{{ .Env.XMPP_MUC_DOMAIN }}"
    breakout_rooms_component = "breakout.{{ .Env.XMPP_DOMAIN }}"
