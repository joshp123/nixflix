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
  cfg = nixflix.bazarr;
  credentialDir = "/run/credentials/bazarr.service";
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);

  mkCredential =
    name: value:
    let
      credentialSource =
        if value == null then
          pkgs.writeText "bazarr-${name}-missing-credential" ""
        else if secrets.isSecretRef value then
          value._secret
        else
          pkgs.writeText "bazarr-${name}-credential" value;
    in
    {
      file = "${credentialDir}/${name}";
      loadCredential = "${name}:${credentialSource}";
    };

  sonarrCredential = mkCredential "sonarr-api-key" cfg.sonarr.apiKey;
  radarrCredential = mkCredential "radarr-api-key" cfg.radarr.apiKey;
  opensubtitlesUsernameCredential = mkCredential "opensubtitlescom-username" cfg.openSubtitlesCom.username;
  opensubtitlesPasswordCredential = mkCredential "opensubtitlescom-password" cfg.openSubtitlesCom.password;
  hasOpenSubtitles = cfg.openSubtitlesCom.username != null || cfg.openSubtitlesCom.password != null;

  ownedValues = {
    general = {
      ip = cfg.endpoint.bindAddress;
      port = cfg.endpoint.port;
      base_url = cfg.endpoint.urlBase;
      use_sonarr = true;
      use_radarr = true;
      analytics_enabled = false;
      minimum_score = 90;
      minimum_score_movie = 80;
      wanted_search_frequency = 876000;
      wanted_search_frequency_movie = 876000;
    };
    auth.type = null;
    sonarr = {
      inherit (cfg.sonarr) port;
      ip = cfg.sonarr.hostname;
      base_url = cfg.sonarr.urlBase;
      ssl = cfg.sonarr.useSsl;
      only_monitored = true;
      series_sync_on_live = false;
      series_sync = 10080;
      full_update = "Manually";
    };
    radarr = {
      inherit (cfg.radarr) port;
      ip = cfg.radarr.hostname;
      base_url = cfg.radarr.urlBase;
      ssl = cfg.radarr.useSsl;
      only_monitored = true;
      movies_sync_on_live = false;
      movies_sync = 10080;
      full_update = "Manually";
    };
    subsync.use_subsync = false;
  }
  // optionalAttrs hasOpenSubtitles {
    opensubtitlescom = {
      use_hash = true;
      include_ai_translated = false;
      include_machine_translated = false;
    };
  };

  policyFile = pkgs.writeText "bazarr-policy.json" (
    builtins.toJSON {
      inherit ownedValues;
      requiredProviders = optional hasOpenSubtitles "opensubtitlescom";
    }
  );
in
{
  options.nixflix.bazarr = {
    enable = mkEnableOption "Bazarr subtitle workflow policy";
    package = mkPackageOption pkgs "bazarr" { };

    dataDir = mkOption {
      type = types.str;
      default = "${nixflix.stateDir}/bazarr";
      defaultText = literalExpression ''"''${config.nixflix.stateDir}/bazarr"'';
      description = "Directory containing Bazarr state and configuration.";
    };

    user = mkOption {
      type = types.str;
      default = "bazarr";
      description = "User under which Bazarr runs.";
    };

    group = mkOption {
      type = types.str;
      default = nixflix.globals.libraryOwner.group;
      defaultText = literalExpression "config.nixflix.globals.libraryOwner.group";
      description = "Group under which Bazarr runs.";
    };

    endpoint = {
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Bazarr bind address.";
      };

      port = mkOption {
        type = types.port;
        default = 6767;
        description = "Bazarr web port.";
      };

      urlBase = mkOption {
        type = types.str;
        default = "/bazarr";
        description = "Bazarr reverse-proxy URL base.";
      };
    };

    sonarr = {
      hostname = mkOption {
        type = types.str;
        default = nixflix.sonarr.connectionAddress or "127.0.0.1";
        description = "Sonarr hostname for Bazarr to call.";
      };

      port = mkOption {
        type = types.port;
        default = nixflix.sonarr.config.hostConfig.port or 8989;
        description = "Sonarr port.";
      };

      urlBase = mkOption {
        type = types.str;
        default = nixflix.sonarr.config.hostConfig.urlBase or "";
        description = "Sonarr URL base.";
      };

      useSsl = mkOption {
        type = types.bool;
        default = nixflix.sonarr.config.hostConfig.enableSsl or false;
        description = "Use HTTPS when Bazarr connects to Sonarr.";
      };

      apiKey = secrets.mkSecretOption {
        nullable = true;
        default = if nixflix.sonarr.enable or false then nixflix.sonarr.config.apiKey else null;
        description = "Sonarr API key used by Bazarr.";
      };
    };

    radarr = {
      hostname = mkOption {
        type = types.str;
        default = nixflix.radarr.connectionAddress or "127.0.0.1";
        description = "Radarr hostname for Bazarr to call.";
      };

      port = mkOption {
        type = types.port;
        default = nixflix.radarr.config.hostConfig.port or 7878;
        description = "Radarr port.";
      };

      urlBase = mkOption {
        type = types.str;
        default = nixflix.radarr.config.hostConfig.urlBase or "";
        description = "Radarr URL base.";
      };

      useSsl = mkOption {
        type = types.bool;
        default = nixflix.radarr.config.hostConfig.enableSsl or false;
        description = "Use HTTPS when Bazarr connects to Radarr.";
      };

      apiKey = secrets.mkSecretOption {
        nullable = true;
        default = if nixflix.radarr.enable or false then nixflix.radarr.config.apiKey else null;
        description = "Radarr API key used by Bazarr.";
      };
    };

    openSubtitlesCom = {
      username = secrets.mkSecretOption {
        nullable = true;
        default = null;
        description = "OpenSubtitlesCom username.";
      };

      password = secrets.mkSecretOption {
        nullable = true;
        default = null;
        description = "OpenSubtitlesCom password.";
      };
    };
  };

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = nixflix.sonarr.enable && cfg.sonarr.apiKey != null;
        message = "nixflix.bazarr requires nixflix.sonarr with an API key.";
      }
      {
        assertion = nixflix.radarr.enable && cfg.radarr.apiKey != null;
        message = "nixflix.bazarr requires nixflix.radarr with an API key.";
      }
      {
        assertion =
          !hasOpenSubtitles
          || (cfg.openSubtitlesCom.username != null && cfg.openSubtitlesCom.password != null);
        message = "nixflix.bazarr.openSubtitlesCom requires both username and password when either credential is configured.";
      }
    ];

    services.bazarr = {
      enable = true;
      inherit (cfg)
        package
        dataDir
        user
        group
        ;
      listenPort = cfg.endpoint.port;
      openFirewall = false;
    };

    users = {
      groups.${cfg.group} = optionalAttrs (nixflix.globals.gids ? ${cfg.group}) {
        gid = nixflix.globals.gids.${cfg.group};
      };
      users.${cfg.user} = {
        inherit (cfg) group;
        home = cfg.dataDir;
        isSystemUser = true;
      }
      // optionalAttrs (nixflix.globals.uids ? ${cfg.user}) {
        uid = nixflix.globals.uids.${cfg.user};
      };
    };

    systemd.tmpfiles.settings."10-bazarr" = {
      "${cfg.dataDir}/config".d = {
        inherit (cfg) user group;
        mode = "0750";
      };
    };

    systemd.services.bazarr = {
      after = [
        "nixflix-setup-dirs.service"
        "sonarr.service"
        "radarr.service"
      ]
      ++ nixflix.serviceDependencies;
      requires = [
        "nixflix-setup-dirs.service"
      ]
      ++ nixflix.serviceDependencies;
      wants = [
        "sonarr.service"
        "radarr.service"
      ];
      environment = {
        BAZARR_POLICY_JSON = policyFile;
        BAZARR_SONARR_API_KEY_FILE = sonarrCredential.file;
        BAZARR_RADARR_API_KEY_FILE = radarrCredential.file;
        BAZARR_REQUIRE_OPENSUBTITLES = if hasOpenSubtitles then "1" else "0";
      }
      // optionalAttrs hasOpenSubtitles {
        BAZARR_OPENSUBTITLES_USERNAME_FILE = opensubtitlesUsernameCredential.file;
        BAZARR_OPENSUBTITLES_PASSWORD_FILE = opensubtitlesPasswordCredential.file;
      };

      serviceConfig = {
        WorkingDirectory = cfg.dataDir;
        LoadCredential = [
          sonarrCredential.loadCredential
          radarrCredential.loadCredential
        ]
        ++ optionals hasOpenSubtitles [
          opensubtitlesUsernameCredential.loadCredential
          opensubtitlesPasswordCredential.loadCredential
        ];
        ExecStartPre =
          "+"
          + pkgs.writeShellScript "bazarr-configure" ''
            set -euo pipefail
            ${pkgs.coreutils}/bin/install -d -o ${escapeShellArg cfg.user} -g ${escapeShellArg cfg.group} -m 0750 ${escapeShellArg "${cfg.dataDir}/config"}
            ${python}/bin/python ${./writeConfig.py} --state-dir ${escapeShellArg cfg.dataDir} --policy ${policyFile}
            ${pkgs.coreutils}/bin/chown ${escapeShellArg "${cfg.user}:${cfg.group}"} ${escapeShellArg "${cfg.dataDir}/config/config.yaml"}
            ${pkgs.coreutils}/bin/chmod 0640 ${escapeShellArg "${cfg.dataDir}/config/config.yaml"}
          '';
      };
    };
  };
}
