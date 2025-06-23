
-- domain mapper options, must at least have domain base set to use the mapper
muc_mapper_domain_base = "{{ .Env.XMPP_DOMAIN }}";
muc_mapper_domain_prefix = "";
recorder_prefixes = { "recorder@{{ .Env.XMPP_HIDDEN_DOMAIN }}" };

http_default_host = "{{ .Env.XMPP_DOMAIN }}"
consider_bosh_secure = true;
consider_websocket_secure = true;
cross_domain_websocket = true;
cross_domain_bosh = false;

-- http_cors_override = {
--    bosh = {
--        enabled = false;
--    };
--    websocket = {
--        enabled = false;
--    };
-- }

admins = {
    "focus@{{ .Env.XMPP_AUTH_DOMAIN }}",
    "jvb@{{ .Env.XMPP_AUTH_DOMAIN }}"
}

unlimited_jids = {
    "focus@{{ .Env.XMPP_AUTH_DOMAIN }}",
    "jvb@{{ .Env.XMPP_AUTH_DOMAIN }}"
}

-- https://prosody.im/doc/modules/mod_smacks
smacks_max_unacked_stanzas = 5;
smacks_hibernation_time = 30;
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
        "conference_duration";
        "end_conference";
        "muc_lobby_rooms";
        "muc_breakout_rooms";
        "av_moderation";
        "room_metadata";
        "features_identity";

        "cf_turncredentials"; -- Support CF TURN/STUN
    }
    c2s_require_encryption = true
    main_muc = "{{ .Env.XMPP_MUC_DOMAIN }}"
    lobby_muc = "lobby.{{ .Env.XMPP_DOMAIN }}"
    breakout_rooms_muc = "breakout.{{ .Env.XMPP_DOMAIN }}"
    room_metadata_component = "metadata.{{ .Env.XMPP_DOMAIN }}"
    -- muc_lobby_whitelist = { "{{ .Env.XMPP_HIDDEN_DOMAIN }}" } -- Here we can whitelist jibri to enter lobby enabled rooms
    smacks_max_hibernated_sessions = 1

VirtualHost "guest.{{ .Env.XMPP_DOMAIN }}"
    authentication = "anonymous"
    c2s_require_encryption = true

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
    -- The size of the cache that saves state for IP addresses
    rate_limit_cache_size = 10000;
    muc_room_cache_size = 10000
    muc_room_locking = false
    muc_room_default_public_jids = true
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
        "ping";
    }
    admins = { "focus@{{ .Env.XMPP_AUTH_DOMAIN }}", "jvb@{{ .Env.XMPP_AUTH_DOMAIN }}" }
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
    muc_room_locking = false
    muc_room_default_public_jids = true
    muc_tombstones = false
    muc_room_allow_persistent = false
    muc_room_cache_size = 10000

Component "breakout.{{ .Env.XMPP_DOMAIN }}" "muc"
    storage = "memory"
    modules_enabled = {
        "muc_hide_all";
        "muc_meeting_id";
        "muc_domain_mapper";
        "muc_rate_limit";
        "polls";
    }
    admins = { "focus@{{ .Env.XMPP_AUTH_DOMAIN }}" }
    restrict_room_creation = true
    muc_room_locking = false
    muc_room_default_public_jids = true
    muc_room_cache_size = 10000
    muc_tombstones = false
    muc_room_allow_persistent = false

-- Proxy to jicofo's user JID, so that it doesn't have to register as a component.
Component "focus.{{ .Env.XMPP_DOMAIN }}" "client_proxy"
    target_address = "focus@{{ .Env.XMPP_AUTH_DOMAIN }}"

Component "speakerstats.{{ .Env.XMPP_DOMAIN }}" "speakerstats_component"
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
