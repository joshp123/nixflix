{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  nixflix = config.nixflix;
  cfg = nixflix.seerr;
  rf = cfg.requestFirst;
  serviceName = "seerr-request-first-policy";
  credentialDir = "/run/credentials/${serviceName}.service";
  requestFirstPermissions = 8352;
  sanitizeName = name: builtins.replaceStrings [ " " "-" "/" ] [ "_" "_" "_" ] name;

  discoverSliderTypeIds = {
    RECENTLY_ADDED = 1;
    RECENT_REQUESTS = 2;
    PLEX_WATCHLIST = 3;
    TRENDING = 4;
    POPULAR_MOVIES = 5;
    MOVIE_GENRES = 6;
    UPCOMING_MOVIES = 7;
    STUDIOS = 8;
    POPULAR_TV = 9;
    TV_GENRES = 10;
    UPCOMING_TV = 11;
    NETWORKS = 12;
  };

  userSettings = {
    defaultPermissions = requestFirstPermissions;
  };

  managedUsers = mapAttrs (name: user: {
    email = user.email;
    permissions = requestFirstPermissions;
  }) rf.managedUsers;

  knownDiscoverTypeIds = attrValues discoverSliderTypeIds;
  enabledDiscoverTypeIds = [ discoverSliderTypeIds.RECENTLY_ADDED ];

  mkCredential =
    prefix: name: apiKey:
    let
      credentialName = "${prefix}-${sanitizeName name}-apikey";
      credentialSource =
        if secrets.isSecretRef apiKey then
          apiKey._secret
        else
          pkgs.writeText "${credentialName}-inline-key" apiKey;
    in
    {
      inherit credentialName credentialSource;
      apiKeyFile = "${credentialDir}/${credentialName}";
      loadCredential = "${credentialName}:${credentialSource}";
    };

  radarrTargetName = "Radarr Best";
  sonarrTargetName = "Sonarr Best";
  bestProfileName = "Best";

  radarrCredential = mkCredential "radarr" radarrTargetName rf.radarr.apiKey;
  sonarrCredential = mkCredential "sonarr" sonarrTargetName rf.sonarr.apiKey;

  radarrTargets = optional rf.radarr.enable ({
    name = radarrTargetName;
    inherit (rf.radarr)
      hostname
      port
      useSsl
      baseUrl
      activeDirectory
      ;
    activeProfileName = bestProfileName;
    is4k = false;
    minimumAvailability = "released";
    isDefault = true;
    externalUrl = "";
    syncEnabled = false;
    preventSearch = false;
    apiKeyFile = radarrCredential.apiKeyFile;
  });

  sonarrTargets = optional rf.sonarr.enable ({
    name = sonarrTargetName;
    inherit (rf.sonarr)
      hostname
      port
      useSsl
      baseUrl
      activeDirectory
      activeAnimeDirectory
      ;
    activeProfileName = bestProfileName;
    activeAnimeProfileName = bestProfileName;
    seriesType = "standard";
    animeSeriesType = "standard";
    enableSeasonFolders = true;
    is4k = false;
    isDefault = true;
    externalUrl = "";
    syncEnabled = false;
    preventSearch = false;
    apiKeyFile = sonarrCredential.apiKeyFile;
  });
in
{
  options.nixflix.seerr.requestFirst = {
    enable = mkEnableOption "request-first Plex-backed Seerr policy";

    plex = {
      hostname = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Plex server hostname or IP address.";
      };

      port = mkOption {
        type = types.port;
        default = 32400;
        description = "Plex server port.";
      };

      useSsl = mkOption {
        type = types.bool;
        default = false;
        description = "Use HTTPS when Seerr connects to Plex.";
      };

      webAppUrl = mkOption {
        type = types.str;
        default = "";
        description = "Optional Plex web app URL stored in Seerr.";
      };
    };

    managedUsers = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              email = mkOption {
                type = types.str;
                default = name;
                description = "Existing Seerr user email address to reconcile.";
              };
            };
          }
        )
      );
      default = { };
      description = "Existing Seerr users whose permissions are part of the request-first policy.";
    };

    radarr = {
      enable = mkOption {
        type = types.bool;
        default = nixflix.radarr.enable or false;
        description = "Configure the request-first default Radarr target in Seerr.";
      };

      hostname = mkOption {
        type = types.str;
        default = nixflix.radarr.connectionAddress or "127.0.0.1";
        description = "Radarr hostname for Seerr to call.";
      };

      port = mkOption {
        type = types.port;
        default = nixflix.radarr.config.hostConfig.port or 7878;
        description = "Radarr port.";
      };

      apiKey = secrets.mkSecretOption {
        nullable = true;
        default = if nixflix.radarr.enable or false then nixflix.radarr.config.apiKey else null;
        description = "Radarr API key used for Seerr's Radarr target.";
      };

      useSsl = mkOption {
        type = types.bool;
        default = false;
        description = "Use HTTPS when Seerr connects to Radarr.";
      };

      baseUrl = mkOption {
        type = types.str;
        default = nixflix.radarr.config.hostConfig.urlBase or "";
        description = "Radarr URL base.";
      };

      activeDirectory = mkOption {
        type = types.str;
        default = toString (head (nixflix.radarr.mediaDirs or [ "/movies" ]));
        description = "Radarr root folder for requests.";
      };

    };

    sonarr = {
      enable = mkOption {
        type = types.bool;
        default = nixflix.sonarr.enable or false;
        description = "Configure the request-first default Sonarr target in Seerr.";
      };

      hostname = mkOption {
        type = types.str;
        default = nixflix.sonarr.connectionAddress or "127.0.0.1";
        description = "Sonarr hostname for Seerr to call.";
      };

      port = mkOption {
        type = types.port;
        default = nixflix.sonarr.config.hostConfig.port or 8989;
        description = "Sonarr port.";
      };

      apiKey = secrets.mkSecretOption {
        nullable = true;
        default = if nixflix.sonarr.enable or false then nixflix.sonarr.config.apiKey else null;
        description = "Sonarr API key used for Seerr's Sonarr target.";
      };

      useSsl = mkOption {
        type = types.bool;
        default = false;
        description = "Use HTTPS when Seerr connects to Sonarr.";
      };

      baseUrl = mkOption {
        type = types.str;
        default = nixflix.sonarr.config.hostConfig.urlBase or "";
        description = "Sonarr URL base.";
      };

      activeDirectory = mkOption {
        type = types.str;
        default = toString (head (nixflix.sonarr.mediaDirs or [ "/tv" ]));
        description = "Sonarr root folder for regular requests.";
      };

      activeAnimeDirectory = mkOption {
        type = types.str;
        default = toString (head (nixflix.sonarr.mediaDirs or [ "/tv" ]));
        description = "Sonarr root folder for anime requests.";
      };

    };
  };

  config = mkIf (nixflix.enable && cfg.enable && rf.enable) {
    assertions = [
      {
        assertion = !cfg.manage.enable;
        message = "nixflix.seerr.requestFirst.enable requires nixflix.seerr.manage.enable = false; it is a restored-state policy and must not enable the broad Jellyfin/setup path.";
      }
      {
        assertion = cfg.apiKey == null;
        message = "nixflix.seerr.requestFirst.enable reads the restored Seerr API key from settings.json; do not set nixflix.seerr.apiKey because it can restage restored API auth.";
      }
      {
        assertion = !rf.radarr.enable || rf.radarr.apiKey != null;
        message = "Seerr request-first Radarr policy requires a Radarr API key.";
      }
      {
        assertion = !rf.sonarr.enable || rf.sonarr.apiKey != null;
        message = "Seerr request-first Sonarr policy requires a Sonarr API key.";
      }
      {
        assertion = requestFirstPermissions == 8352;
        message = "Seerr request-first policy must keep default permissions at 8352 unless the policy is deliberately redesigned.";
      }
      {
        assertion = enabledDiscoverTypeIds == [ 1 ];
        message = "Seerr request-first policy must keep only the Recently Added built-in discover slider enabled unless the policy is deliberately redesigned.";
      }
    ];

    systemd.services.${serviceName} = {
      description = "Apply restored-state request-first Seerr policy";
      after = [
        "seerr.service"
      ]
      ++ optional rf.radarr.enable "radarr.service"
      ++ optional rf.sonarr.enable "sonarr.service";
      requires = [ "seerr.service" ];
      wants = optional rf.radarr.enable "radarr.service" ++ optional rf.sonarr.enable "sonarr.service";
      wantedBy = [ "multi-user.target" ];

      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.gnused
        pkgs.jq
        pkgs.sqlite
      ];

      environment = {
        SEERR_BASE_URL = "http://${cfg.connectionAddress}:${toString cfg.port}";
        SEERR_SETTINGS_JSON = "${cfg.dataDir}/settings.json";
        SEERR_DB = "${cfg.dataDir}/db/db.sqlite3";
        SEERR_USER_SETTINGS_JSON = pkgs.writeText "seerr-request-first-user-settings.json" (
          builtins.toJSON userSettings
        );
        SEERR_MANAGED_USERS_JSON = pkgs.writeText "seerr-request-first-managed-users.json" (
          builtins.toJSON managedUsers
        );
        SEERR_DISCOVER_ENABLED_TYPES_JSON = pkgs.writeText "seerr-request-first-discover-types.json" (
          builtins.toJSON enabledDiscoverTypeIds
        );
        SEERR_DISCOVER_KNOWN_TYPES_JSON = pkgs.writeText "seerr-request-first-discover-known-types.json" (
          builtins.toJSON knownDiscoverTypeIds
        );
        SEERR_RADARR_TARGETS_JSON = pkgs.writeText "seerr-request-first-radarr-targets.json" (
          builtins.toJSON radarrTargets
        );
        SEERR_SONARR_TARGETS_JSON = pkgs.writeText "seerr-request-first-sonarr-targets.json" (
          builtins.toJSON sonarrTargets
        );
        SEERR_PLEX_HOSTNAME = rf.plex.hostname;
        SEERR_PLEX_PORT = toString rf.plex.port;
        SEERR_PLEX_USE_SSL = boolToString rf.plex.useSsl;
        SEERR_PLEX_WEB_APP_URL = rf.plex.webAppUrl;
      };

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        LoadCredential =
          optional rf.radarr.enable radarrCredential.loadCredential
          ++ optional rf.sonarr.enable sonarrCredential.loadCredential;
      };

      script = builtins.readFile ./requestFirstPolicy.sh;
    };
  };
}
