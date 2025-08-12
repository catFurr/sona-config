-- working jitsi-meet.cfg.lua

admins = {
    -- "jigasi@auth.{{ .Env.XMPP_DOMAIN }}",
    -- "jibri@auth.{{ .Env.XMPP_DOMAIN }}",

    "focus@auth.{{ .Env.XMPP_DOMAIN }}",
    "jvb@auth.{{ .Env.XMPP_DOMAIN }}"
}

unlimited_jids = {
    "focus@auth.{{ .Env.XMPP_DOMAIN }}",
    "jvb@auth.{{ .Env.XMPP_DOMAIN }}"
}

plugin_paths = { "/prosody-plugins/", "/prosody-plugins-custom", "/prosody-plugins-contrib" }

muc_mapper_domain_base = "{{ .Env.XMPP_DOMAIN }}";
muc_mapper_domain_prefix = "conference";

recorder_prefixes = { "recorder@recorder.{{ .Env.XMPP_DOMAIN }}" };

http_default_host = "{{ .Env.XMPP_DOMAIN }}"


-- https://prosody.im/doc/modules/mod_smacks
smacks_max_unacked_stanzas = 5;
smacks_hibernation_time = 30;
smacks_max_old_sessions = 1;


VirtualHost "{{ .Env.XMPP_DOMAIN }}"
    authentication = "token"
    app_id = "jitsi-meet"
    asap_key_server = true
    cache_keys_url = "{{ .Env.KC_HOST_URL }}realms/jitsi/protocol/openid-connect/certs"
    asap_accepted_issuers = { "{{ .Env.KC_HOST_URL }}realms/jitsi" }
    asap_accepted_audiences = { "jitsi-web", "account" }
    asap_require_room_claim = true
    allow_empty_token = false
    enable_domain_verification = false
    -- app_secret="example_app_secret"
    modules_enabled = {
        "bosh";

        "websocket";
        "smacks"; -- XEP-0198: Stream Management
        "ping"; -- Enable mod_ping

        "features_identity"; -- New module to announce features
        "conference_duration";

        "muc_lobby_rooms";
        "muc_breakout_rooms";
    }

    main_muc = "conference.{{ .Env.XMPP_DOMAIN }}"
    room_metadata_component = "metadata.{{ .Env.XMPP_DOMAIN }}"
    lobby_muc = "lobby.{{ .Env.XMPP_DOMAIN }}"
    breakout_rooms_muc = "breakout.{{ .Env.XMPP_DOMAIN }}"
    speakerstats_component = "speakerstats.{{ .Env.XMPP_DOMAIN }}"
    end_conference_component = "endconference.{{ .Env.XMPP_DOMAIN }}"
    av_moderation_component = "avmoderation.{{ .Env.XMPP_DOMAIN }}"
    c2s_require_encryption = false
    muc_lobby_whitelist = { "recorder.{{ .Env.XMPP_DOMAIN }}" } -- Here we can whitelist jibri to enter lobby enabled rooms
    -- smacks_max_hibernated_sessions = 1

VirtualHost "guest.{{ .Env.XMPP_DOMAIN }}"
    authentication = "anonymous"
    modules_enabled = {
        "smacks"; -- XEP-0198: Stream Management
    }
    main_muc = "conference.{{ .Env.XMPP_DOMAIN }}"
    c2s_require_encryption = false

VirtualHost "auth.{{ .Env.XMPP_DOMAIN }}"
    modules_enabled = {
        "limits_exception";
        "smacks";
    }
    authentication = "internal_hashed"
    smacks_hibernation_time = 15;

-- internal muc component
Component "internal-muc.{{ .Env.XMPP_DOMAIN }}" "muc"
    storage = "memory"
    modules_enabled = {
        "muc_hide_all";
        "muc_filter_access";
        "ping";
    }
    admins = { "focus@auth.{{ .Env.XMPP_DOMAIN }}", "jvb@auth.{{ .Env.XMPP_DOMAIN }}" }
    restrict_room_creation = true
    muc_filter_whitelist="auth.{{ .Env.XMPP_DOMAIN }}"
    muc_room_locking = false
    muc_room_default_public_jids = true
    muc_room_cache_size = 1000
    muc_tombstones = false
    muc_room_allow_persistent = false

Component "conference.{{ .Env.XMPP_DOMAIN }}" "muc"
    restrict_room_creation = true
    storage = "memory"
    modules_enabled = {
        "muc_meeting_id";
        "polls";
        "muc_domain_mapper";
        "muc_password_whitelist";

        "token_verification";
        "muc_hide_all";
        "muc_rate_limit";
        "muc_max_occupants";
        -- Custom: meeting host management (assign moderators, schedule destruction)
        "meeting_host";
    }
    admins = { "focus@auth.{{ .Env.XMPP_DOMAIN }}" }
    -- The size of the cache that saves state for IP addresses
    rate_limit_cache_size = 10000;
    muc_room_cache_size = 10000
    muc_room_locking = false
    muc_room_default_public_jids = true
    muc_password_whitelist = {
        "focus@auth.{{ .Env.XMPP_DOMAIN }}";
    }
    muc_tombstones = false
    muc_room_allow_persistent = false
    muc_access_whitelist = {
        "focus@auth.{{ .Env.XMPP_DOMAIN }}";
    }
    muc_max_occupants = 100
    meeting_host_destroy_delay = 300

VirtualHost "recorder.{{ .Env.XMPP_DOMAIN }}"
    modules_enabled = {
      "smacks";
    }
    authentication = "internal_hashed"
    smacks_max_old_sessions = 2000;

Component "lobby.{{ .Env.XMPP_DOMAIN }}" "muc"
    storage = "memory"
    restrict_room_creation = true
    muc_tombstones = false
    muc_room_allow_persistent = false
    muc_room_cache_size = 10000
    muc_room_locking = false
    muc_room_default_public_jids = true
    modules_enabled = {
        "muc_hide_all";
        "muc_rate_limit";
        "polls";
    }

Component "breakout.{{ .Env.XMPP_DOMAIN }}" "muc"
    storage = "memory"
    modules_enabled = {
        "muc_meeting_id";
        "polls";

        "muc_hide_all";
        "muc_domain_mapper";
        "muc_rate_limit";
    }
    admins = { "focus@auth.{{ .Env.XMPP_DOMAIN }}" }
    restrict_room_creation = true
    muc_room_cache_size = 10000
    muc_room_locking = false
    muc_room_default_public_jids = true
    muc_tombstones = false
    muc_room_allow_persistent = false

-- Proxy to jicofo's user JID, so that it doesn't have to register as a component.
Component "focus.{{ .Env.XMPP_DOMAIN }}" "client_proxy"
    target_address = "focus@auth.{{ .Env.XMPP_DOMAIN }}"

Component "speakerstats.{{ .Env.XMPP_DOMAIN }}" "speakerstats_component"
    muc_component = "conference.{{ .Env.XMPP_DOMAIN }}"

Component "endconference.{{ .Env.XMPP_DOMAIN }}" "end_conference"
    muc_component = "conference.{{ .Env.XMPP_DOMAIN }}"

Component "avmoderation.{{ .Env.XMPP_DOMAIN }}" "av_moderation_component"
    muc_component = "conference.{{ .Env.XMPP_DOMAIN }}"

Component "filesharing.{{ .Env.XMPP_DOMAIN }}" "filesharing_component"
    muc_component = "conference.{{ .Env.XMPP_DOMAIN }}"

Component "metadata.{{ .Env.XMPP_DOMAIN }}" "room_metadata_component"
    muc_component = "conference.{{ .Env.XMPP_DOMAIN }}"
    breakout_rooms_component = "breakout.{{ .Env.XMPP_DOMAIN }}"
