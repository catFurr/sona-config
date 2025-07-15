
admins = {
    "focus@{{ .Env.XMPP_AUTH_DOMAIN }}",
    "jvb@{{ .Env.XMPP_AUTH_DOMAIN }}"
}

unlimited_jids = {
    "focus@{{ .Env.XMPP_AUTH_DOMAIN }}",
    "jvb@{{ .Env.XMPP_AUTH_DOMAIN }}"
}

plugin_paths = { "/prosody-plugins/", "/prosody-plugins-custom", "/prosody-plugins-contrib" }

-- domain mapper options, must at least have domain base set to use the mapper
muc_mapper_domain_base = "{{ .Env.XMPP_DOMAIN }}";
muc_mapper_domain_prefix = "conference";

recorder_prefixes = { "recorder@{{ .Env.XMPP_HIDDEN_DOMAIN }}" };

http_default_host = "{{ .Env.XMPP_DOMAIN }}"

-- http_cors_override = {
--    bosh = {
--        enabled = false;
--    };
--    websocket = {
--        enabled = false;
--    };
-- }
consider_bosh_secure = true;
consider_websocket_secure = true;
cross_domain_websocket = true;
cross_domain_bosh = false;

-- https://prosody.im/doc/modules/mod_smacks
smacks_max_unacked_stanzas = 5;
smacks_hibernation_time = 60;
smacks_max_old_sessions = 1;

-- Cloudflare TURN configuration
cf_turn_app_id = "{{ .Env.CF_TURN_APP_ID }}"
cf_turn_app_secret = "{{ .Env.CF_TURN_APP_SECRET }}"


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
        "smacks";
        "speakerstats";
        "conference_duration";
        "room_metadata";
        "end_conference";
        "muc_lobby_rooms";
        "muc_breakout_rooms";
        "av_moderation";

        "cf_turncredentials"; -- Support CF TURN/STUN
    }
    main_muc = "{{ .Env.XMPP_MUC_DOMAIN }}"
    room_metadata_component = "metadata.{{ .Env.XMPP_DOMAIN }}"
    lobby_muc = "lobby.{{ .Env.XMPP_DOMAIN }}"
    breakout_rooms_muc = "breakout.{{ .Env.XMPP_DOMAIN }}"
    speakerstats_component = "speakerstats.{{ .Env.XMPP_DOMAIN }}"
    conference_duration_component = "conferenceduration.{{ .Env.XMPP_DOMAIN }}"
    end_conference_component = "endconference.{{ .Env.XMPP_DOMAIN }}"
    av_moderation_component = "avmoderation.{{ .Env.XMPP_DOMAIN }}"
    c2s_require_encryption = true
    -- muc_lobby_whitelist = { "{{ .Env.XMPP_HIDDEN_DOMAIN }}" } -- Here we can whitelist jibri to enter lobby enabled rooms
    -- smacks_max_hibernated_sessions = 1

VirtualHost "guest.{{ .Env.XMPP_DOMAIN }}"
    authentication = "anonymous"
    c2s_require_encryption = false

Component "{{ .Env.XMPP_MUC_DOMAIN }}" "muc"
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
    }
    -- The size of the cache that saves state for IP addresses
    rate_limit_cache_size = 10000;
    muc_room_cache_size = 10000
    muc_room_locking = false
    muc_room_default_public_jids = true
    -- admins = { "focus@{{ .Env.XMPP_AUTH_DOMAIN }}" }
    muc_password_whitelist = {
        "focus@{{ .Env.XMPP_AUTH_DOMAIN }}"
    }
    muc_tombstones = false
    muc_room_allow_persistent = false

VirtualHost "{{ .Env.XMPP_AUTH_DOMAIN }}"
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

-- internal muc component
Component "{{ .Env.XMPP_INTERNAL_MUC_DOMAIN }}" "muc"
    storage = "memory"
    modules_enabled = {
        "muc_hide_all";
        "muc_filter_access";
    }
    -- admins = { "focus@{{ .Env.XMPP_AUTH_DOMAIN }}", "jvb@{{ .Env.XMPP_AUTH_DOMAIN }}" }
    restrict_room_creation = true
    muc_filter_whitelist="{{ .Env.XMPP_AUTH_DOMAIN }}"
    muc_room_locking = false
    muc_room_default_public_jids = true
    muc_room_cache_size = 1000
    muc_tombstones = false
    muc_room_allow_persistent = false

Component "lobby.{{ .Env.XMPP_DOMAIN }}" "muc"
    storage = "memory"
    modules_enabled = {
        "muc_hide_all";
        "muc_rate_limit";
        "polls";
    }
    restrict_room_creation = true
    muc_tombstones = false
    muc_room_allow_persistent = false
    muc_room_cache_size = 10000
    muc_room_locking = false
    muc_room_default_public_jids = true

Component "breakout.{{ .Env.XMPP_DOMAIN }}" "muc"
    storage = "memory"
    modules_enabled = {
        "muc_meeting_id";
        "polls";
        "muc_hide_all";
        "muc_domain_mapper";
        "muc_rate_limit";
    }
    -- admins = { "focus@{{ .Env.XMPP_AUTH_DOMAIN }}" }
    restrict_room_creation = true
    muc_room_cache_size = 10000
    muc_room_locking = false
    muc_room_default_public_jids = true
    muc_tombstones = false
    muc_room_allow_persistent = false

-- Proxy to jicofo's user JID, so that it doesn't have to register as a component.
Component "focus.{{ .Env.XMPP_DOMAIN }}" "client_proxy"
    target_address = "focus@{{ .Env.XMPP_AUTH_DOMAIN }}"

Component "speakerstats.{{ .Env.XMPP_DOMAIN }}" "speakerstats_component"
    muc_component = "{{ .Env.XMPP_MUC_DOMAIN }}"

Component "conferenceduration.{{ .Env.XMPP_DOMAIN }}" "conference_duration_component"
    muc_component = "{{ .Env.XMPP_MUC_DOMAIN }}"

Component "endconference.{{ .Env.XMPP_DOMAIN }}" "end_conference"
    muc_component = "{{ .Env.XMPP_MUC_DOMAIN }}"

Component "avmoderation.{{ .Env.XMPP_DOMAIN }}" "av_moderation_component"
    muc_component = "{{ .Env.XMPP_MUC_DOMAIN }}"

Component "metadata.{{ .Env.XMPP_DOMAIN }}" "room_metadata_component"
    muc_component = "{{ .Env.XMPP_MUC_DOMAIN }}"
    breakout_rooms_component = "breakout.{{ .Env.XMPP_DOMAIN }}"

-- Disable components defined by the default container image
Component "internal-muc.meet.jitsi" "muc"
    enabled = false

Component "muc.meet.jitsi" "muc"
    enabled = false
