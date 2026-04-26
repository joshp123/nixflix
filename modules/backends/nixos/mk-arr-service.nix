{
  config,
  lib,
  pkgs,
  ...
}:
serviceName:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
  inherit (config.nixflix) globals;
  cfg = config.nixflix.${serviceName};
  stateDir = "${config.nixflix.stateDir}/${serviceName}";

  mkWaitForApiScript = import ../../arr-common/mkWaitForApiScript.nix { inherit lib pkgs; };
  mkNixosOneshotService = import ./mk-oneshot-service.nix { inherit lib pkgs; };
  hostConfig = import ../../arr-common/hostConfig.nix { inherit lib pkgs serviceName; };
  rootFolders = import ../../arr-common/rootFolders.nix {
    inherit
      config
      lib
      pkgs
      serviceName
      ;
  };
  delayProfiles = import ../../arr-common/delayProfiles.nix { inherit lib pkgs serviceName; };
  qualityProfiles = import ../../arr-common/qualityProfiles.nix { inherit lib pkgs serviceName; };
  customFormats = import ../../arr-common/customFormats.nix { inherit lib pkgs serviceName; };
  mkServarrSettingsEnvVars = import ../../arr-common/mkServarrSettingsEnvVars.nix { inherit lib; };
  capitalizedName = toUpper (substring 0 1 serviceName) + substring 1 (-1) serviceName;
  usesMediaDirs = !(elem serviceName [ "prowlarr" ]);
  hostname = "${cfg.subdomain}.${config.nixflix.nginx.domain}";
  serviceBase = builtins.elemAt (splitString "-" serviceName) 0;
in
{
  config = mkIf (config.nixflix.enable && cfg.enable) {
    nixflix.${serviceName}.settings = optionalAttrs config.nixflix.postgres.enable {
      log.dbEnabled = true;
      postgres = {
        inherit (cfg) user;
        inherit (config.services.postgresql.settings) port;
        host = "/run/postgresql";
        mainDb = cfg.user;
        logDb = "${cfg.user}-logs";
      };
    };

    services = {
      postgresql = mkIf config.nixflix.postgres.enable {
        ensureDatabases = [
          cfg.settings.postgres.mainDb
          cfg.settings.postgres.logDb
        ];
        ensureUsers = [ { name = cfg.user; } ];
      };

      nginx.virtualHosts."${hostname}" = mkIf config.nixflix.nginx.enable {
        inherit (config.nixflix.nginx) forceSSL;
        useACMEHost = if config.nixflix.nginx.enableACME then config.nixflix.nginx.domain else null;

        locations."/" =
          let
            themeParkUrl = "https://theme-park.dev/css/base/${serviceBase}/${config.nixflix.theme.name}.css";
          in
          {
            proxyPass = "http://127.0.0.1:${builtins.toString cfg.config.hostConfig.port}";
            recommendedProxySettings = true;
            extraConfig = ''
              proxy_redirect off;

              ${
                if config.nixflix.theme.enable then
                  ''
                    proxy_set_header Accept-Encoding "";
                    sub_filter '</body>' '<link rel="stylesheet" type="text/css" href="${themeParkUrl}"></body>';
                    sub_filter_once on;
                  ''
                else
                  ""
              }
            '';
          };
      };
    };

    networking.hosts = mkIf (config.nixflix.nginx.enable && config.nixflix.nginx.addHostsEntries) {
      "127.0.0.1" = [ hostname ];
    };

    users = {
      groups.${cfg.group} = optionalAttrs (globals.gids ? ${cfg.group}) {
        gid = globals.gids.${cfg.group};
      };
      users.${cfg.user} = {
        inherit (cfg) group;
        home = stateDir;
        isSystemUser = true;
      }
      // optionalAttrs (globals.uids ? ${cfg.user}) {
        uid = globals.uids.${cfg.user};
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.config.hostConfig.port ];
    };

    systemd.tmpfiles.settings."10-${serviceName}" = {
      "${stateDir}".d = {
        inherit (cfg) user group;
        mode = "0755";
      };
    }
    // optionalAttrs usesMediaDirs (
      lib.mergeAttrsList (
        map (mediaDir: {
          "${mediaDir}".d = {
            inherit (globals.libraryOwner) user group;
            mode = "0775";
          };
        }) cfg.mediaDirs
      )
    );

    systemd.services = {
      "${serviceName}-setup-logs-db" = mkIf config.nixflix.postgres.enable {
        description = "Grant ownership of ${capitalizedName} databases";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        requires = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        before = [ "postgresql-ready.target" ];
        requiredBy = [ "postgresql-ready.target" ];

        serviceConfig = {
          User = "postgres";
          Group = "postgres";
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          ${pkgs.postgresql}/bin/psql  -tAc 'ALTER DATABASE "${cfg.settings.postgres.mainDb}" OWNER TO "${cfg.user}";'
          ${pkgs.postgresql}/bin/psql  -tAc 'ALTER DATABASE "${cfg.settings.postgres.logDb}" OWNER TO "${cfg.user}";'
        '';
      };

      "${serviceName}-wait-for-db" = mkIf config.nixflix.postgres.enable {
        description = "Wait for ${capitalizedName} PostgreSQL databases to be ready";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        before = [ "postgresql-ready.target" ];
        requiredBy = [ "postgresql-ready.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "5min";
          User = cfg.user;
          Group = cfg.group;
        };

        script = ''
          while true; do
            if ${pkgs.postgresql}/bin/psql -h /run/postgresql -d ${cfg.user} -c "SELECT 1" > /dev/null 2>&1 && \
               ${pkgs.postgresql}/bin/psql -h /run/postgresql -d ${cfg.user}-logs -c "SELECT 1" > /dev/null 2>&1; then
              echo "${capitalizedName} PostgreSQL databases are ready"
              exit 0
            fi
            echo "Waiting for ${capitalizedName} PostgreSQL databases..."
            sleep 1
          done
        '';
      };

      ${serviceName} = {
        description = capitalizedName;
        environment = mkServarrSettingsEnvVars (toUpper serviceBase) cfg.settings;

        after = [
          "network.target"
          "nixflix-setup-dirs.service"
        ]
        ++ config.nixflix.serviceDependencies
        ++ (optional (
          cfg.config.apiKey != null && cfg.config.hostConfig.password != null
        ) "${serviceName}-env.service")
        ++ (optional config.nixflix.postgres.enable "postgresql-ready.target")
        ++ (optional config.nixflix.mullvad.enable "mullvad-config.service");
        requires = [
          "nixflix-setup-dirs.service"
        ]
        ++ config.nixflix.serviceDependencies
        ++ (optional (
          cfg.config.apiKey != null && cfg.config.hostConfig.password != null
        ) "${serviceName}-env.service")
        ++ (optional config.nixflix.postgres.enable "postgresql-ready.target");
        wants = optional config.nixflix.mullvad.enable "mullvad-config.service";
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          ExecStart = "${getExe cfg.package} -nobrowser -data='${stateDir}'";
          ExecStartPost = "+" + (mkWaitForApiScript serviceName cfg.config);
          Restart = "on-failure";
        }
        // optionalAttrs (cfg.config.apiKey != null && cfg.config.hostConfig.password != null) {
          EnvironmentFile = "/run/${serviceName}/env";
        }
        // optionalAttrs (config.nixflix.mullvad.enable && !cfg.vpn.enable) {
          ExecStart = mkForce (
            pkgs.writeShellScript "${serviceName}-vpn-bypass" ''
              exec /run/wrappers/bin/mullvad-exclude ${getExe cfg.package} \
                -nobrowser -data='${stateDir}'
            ''
          );
          AmbientCapabilities = "CAP_SYS_ADMIN";
          Delegate = mkForce true;
        };
      };
    }
    // optionalAttrs (cfg.config.apiKey != null && cfg.config.hostConfig.password != null) {
      "${serviceName}-env" = {
        description = "Setup ${capitalizedName} environment file";
        wantedBy = [ "${serviceName}.service" ];
        before = [ "${serviceName}.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = ''
          mkdir -p /run/${serviceName}
          echo "${
            toUpper serviceBase + "__AUTH__APIKEY"
          }=${secrets.toShellValue cfg.config.apiKey}" > /run/${serviceName}/env
          chown ${cfg.user}:${cfg.group} /run/${serviceName}/env
          chmod 0400 /run/${serviceName}/env
        '';
      };

      "${serviceName}-config" = mkNixosOneshotService (hostConfig.mkJob cfg.config);
    }
    // optionalAttrs (usesMediaDirs && cfg.config.apiKey != null && cfg.config.rootFolders != [ ]) {
      "${serviceName}-rootfolders" = mkNixosOneshotService (rootFolders.mkJob cfg.config);
    }
    // optionalAttrs (usesMediaDirs && cfg.config.apiKey != null) {
      "${serviceName}-delayprofiles" = mkNixosOneshotService (delayProfiles.mkJob cfg.config);
    }
    // optionalAttrs (usesMediaDirs && cfg.config.apiKey != null && cfg.config.qualityProfiles != [ ]) {
      "${serviceName}-qualityprofiles" = mkNixosOneshotService (qualityProfiles.mkJob cfg.config);
    }
    // optionalAttrs (usesMediaDirs && cfg.config.apiKey != null && cfg.config.customFormats != [ ]) {
      "${serviceName}-customformats" = mkNixosOneshotService (customFormats.mkJob cfg.config);
    };
  };
}
