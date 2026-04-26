{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../../lib/secrets { inherit lib; };
  cfg = config.nixflix.bazarr;
  stateDir = "${config.nixflix.stateDir}/bazarr";
  logDir = "${stateDir}/logs";
  activateBazarr = builtins.path {
    path = ./scripts/activate-bazarr.sh;
    name = "activate-bazarr.sh";
  };
  writeConfig = pkgs.replaceVars ./scripts/write-bazarr-config.sh {
    jq = "${pkgs.jq}/bin/jq";
  };
  hasOpenSubtitles = cfg.config.opensubtitlescom.username != null;
  configTemplate = pkgs.writeText "bazarr-config-template.json" (
    builtins.toJSON {
      general = {
        ip = cfg.config.bindAddress;
        port = cfg.config.port;
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
        ip = "127.0.0.1";
        port = 8989;
        base_url = "/sonarr";
        ssl = false;
        apikey = "";
        only_monitored = true;
        series_sync_on_live = false;
        series_sync = 10080;
        full_update = "Manually";
      };
      radarr = {
        ip = "127.0.0.1";
        port = 7878;
        base_url = "/radarr";
        ssl = false;
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
  secretArgs =
    value:
    if value == null then
      [
        "empty"
        ""
      ]
    else if secrets.isSecretRef value then
      [
        "file"
        (toString value._secret)
      ]
    else
      [
        "literal"
        (toString value)
      ];
  serviceSpec = {
    name = "bazarr";
    argv = [
      "${getExe cfg.package}"
      "--no-update"
      "-c"
      stateDir
      "-p"
      (toString cfg.config.port)
    ];
    cwd = stateDir;
    stdout = "${logDir}/stdout.log";
    stderr = "${logDir}/stderr.log";
    env = {
      HOME = stateDir;
      PATH = "${lib.makeBinPath [ pkgs.coreutils ]}:/usr/bin:/bin:/usr/sbin:/sbin";
    };
  };
in
{
  imports = [ ../../bazarr.nix ];

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.user != "root" && cfg.group != "wheel";
        message = "nixflix.bazarr must not run as root:wheel on Darwin.";
      }
    ];

    nixflix.bazarr = {
      user = mkOverride 900 "nixflix";
      group = mkOverride 900 "staff";
    };

    system.activationScripts.postActivation.text = mkOrder 2000 (
      "/bin/bash ${
        escapeShellArgs (
          [
            activateBazarr
            stateDir
            logDir
            cfg.user
            cfg.group
            writeConfig
            configTemplate
          ]
          ++ secretArgs cfg.config.sonarrApiKey
          ++ secretArgs cfg.config.radarrApiKey
          ++ secretArgs cfg.config.opensubtitlescom.username
          ++ secretArgs cfg.config.opensubtitlescom.password
        )
      }\n"
    );

    nixflix.runtime.darwinSupervisorManifest.services = [ serviceSpec ];
  };
}
