{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
  inherit (config.nixflix) globals;
  cfg = config.nixflix.bazarr;
  stateDir = "${config.nixflix.stateDir}/bazarr";
  logDir = "${stateDir}/logs";
  mkLocalArrHost =
    hostConfig:
    let
      inherit (hostConfig) bindAddress;
    in
    if bindAddress == "*" || bindAddress == "0.0.0.0" then "127.0.0.1" else bindAddress;
  writeConfig = pkgs.replaceVars ../darwin/scripts/write-bazarr-config.sh {
    jq = "${pkgs.jq}/bin/jq";
    mkdir = "${pkgs.coreutils}/bin/mkdir";
  };
  sonarrHostConfig = config.nixflix.sonarr.config.hostConfig;
  radarrHostConfig = config.nixflix.radarr.config.hostConfig;
  mkArrDependencies =
    serviceName: serviceConfig:
    optionals serviceConfig.enable (
      [ "${serviceName}.service" ]
      ++ optional (
        serviceConfig.config.apiKey != null && serviceConfig.config.hostConfig.password != null
      ) "${serviceName}-config.service"
    );
  arrServiceDependencies =
    mkArrDependencies "sonarr" config.nixflix.sonarr
    ++ mkArrDependencies "radarr" config.nixflix.radarr;
  hasOpenSubtitles = cfg.config.opensubtitlescom.username != null;
  configTemplate = pkgs.writeText "bazarr-config-template.json" (
    builtins.toJSON {
      general = {
        ip = cfg.config.bindAddress;
        inherit (cfg.config) port;
        base_url = cfg.config.urlBase;
        use_sonarr = true;
        use_radarr = true;
        enabled_providers = optional hasOpenSubtitles "opensubtitlescom";
        analytics_enabled = false;
        minimum_score = 90;
        minimum_score_movie = 80;
        wanted_search_frequency = 876000;
        wanted_search_frequency_movie = 876000;
        upgrade_subs = false;
        upgrade_frequency = 876000;
        adaptive_searching = false;
        use_embedded_subs = true;
      };
      auth.type = null;
      sonarr = {
        ip = mkLocalArrHost sonarrHostConfig;
        inherit (sonarrHostConfig) port;
        base_url = sonarrHostConfig.urlBase;
        ssl = sonarrHostConfig.enableSsl;
        apikey = "";
        only_monitored = true;
        series_sync_on_live = false;
        series_sync = 10080;
        full_update = "Manually";
      };
      radarr = {
        ip = mkLocalArrHost radarrHostConfig;
        inherit (radarrHostConfig) port;
        base_url = radarrHostConfig.urlBase;
        ssl = radarrHostConfig.enableSsl;
        apikey = "";
        only_monitored = true;
        movies_sync_on_live = false;
        movies_sync = 10080;
        full_update = "Manually";
      };
      opensubtitlescom = {
        username = "";
        password = "";
        use_hash = true;
        include_ai_translated = false;
        include_machine_translated = false;
      };
      subsync.use_subsync = false;
    }
  );
  optionalSecretValue = value: optionalString (value != null) (secrets.toShellValue value);
in
{
  config = mkIf (config.nixflix.enable && cfg.enable) {
    nixflix.bazarr.group = mkDefault globals.libraryOwner.group;

    services.bazarr = {
      enable = true;
      inherit (cfg) package user group;
      dataDir = stateDir;
      listenPort = cfg.config.port;
      openFirewall = false;
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

    systemd.tmpfiles.settings."10-bazarr" = {
      "${stateDir}".d = {
        user = mkForce cfg.user;
        group = mkForce cfg.group;
        mode = mkForce "0755";
      };
      "${logDir}".d = {
        inherit (cfg) user group;
        mode = "0755";
      };
    };

    systemd.services.bazarr = {
      after = [
        "nixflix-setup-dirs.service"
      ]
      ++ arrServiceDependencies
      ++ config.nixflix.serviceDependencies;
      requires = [
        "nixflix-setup-dirs.service"
      ]
      ++ arrServiceDependencies
      ++ config.nixflix.serviceDependencies;
      environment.HOME = stateDir;

      serviceConfig = {
        WorkingDirectory = stateDir;
        ExecStartPre =
          "+"
          + pkgs.writeShellScript "bazarr-configure" ''
            set -euo pipefail

            export BAZARR_SONARR_API_KEY=${secrets.toShellValue cfg.config.sonarrApiKey}
            export BAZARR_RADARR_API_KEY=${secrets.toShellValue cfg.config.radarrApiKey}
            export BAZARR_OPENSUBTITLES_USERNAME=${optionalSecretValue cfg.config.opensubtitlescom.username}
            export BAZARR_OPENSUBTITLES_PASSWORD=${optionalSecretValue cfg.config.opensubtitlescom.password}
            export BAZARR_REQUIRE_OPENSUBTITLES=${if hasOpenSubtitles then "1" else "0"}

            ${writeConfig} ${escapeShellArg stateDir} ${configTemplate}
            ${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.group} ${escapeShellArg stateDir}
          '';
      };
    };
  };
}
