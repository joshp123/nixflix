{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;
  mkLaunchdService = import ./mk-launchd-service.nix { inherit lib; };
  mkLaunchdOneshot = import ./mk-launchd-oneshot.nix { inherit pkgs; };
  xml = import ../../jellyfin/xml.nix { inherit lib; };
  networkXmlContent = xml.mkXmlContent "NetworkConfiguration" cfg.network;
  networkXmlFile = pkgs.writeText "jellyfin-network.xml" networkXmlContent;
  stateDir = cfg.dataDir;
  commonPath = "${
    lib.makeBinPath [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jellyfin
      pkgs.jq
      pkgs.sqlite
    ]
  }:/usr/bin:/bin:/usr/sbin:/sbin";
  waitForApiScript = import ../../jellyfin/waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };
  apiKeyJob = import ../../jellyfin/mkApiKeyJob.nix { inherit cfg lib pkgs; };
  setupWizardJob = import ../../jellyfin/mkSetupWizardJob.nix { inherit cfg lib pkgs; };
  systemConfigJob = import ../../jellyfin/mkSystemConfigJob.nix { inherit cfg lib pkgs; };
  usersConfigJob = import ../../jellyfin/mkUsersConfigJob.nix { inherit cfg lib pkgs; };
  librariesJob = import ../../jellyfin/mkLibrariesJob.nix {
    inherit
      config
      cfg
      lib
      pkgs
      ;
  };
  brandingJob = import ../../jellyfin/mkBrandingJob.nix { inherit cfg lib pkgs; };
  encodingJob = import ../../jellyfin/mkEncodingJob.nix { inherit cfg lib pkgs; };
in
{
  imports = [ ../../jellyfin/options ];

  config = mkIf (nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = !cfg.openFirewall;
        message = "nixflix.jellyfin.openFirewall is not implemented on Darwin yet.";
      }
      {
        assertion = !cfg.vpn.enable;
        message = "nixflix.jellyfin.vpn.enable is not implemented on Darwin yet.";
      }
      {
        assertion = !nixflix.nginx.enable;
        message = "nixflix.nginx is not implemented for Jellyfin on Darwin yet.";
      }
      {
        assertion = any (user: user.policy.isAdministrator) (attrValues cfg.users);
        message = "At least one Jellyfin user must have policy.isAdministrator = true.";
      }
      {
        assertion = cfg.system.cacheSize >= 3;
        message = "nixflix.jellyfin.system.cacheSize must be at least 3 due to Jellyfin's internal caching implementation (got ${toString cfg.system.cacheSize}).";
      }
      {
        assertion = cfg.user != "root" && cfg.group != "wheel";
        message = "nixflix.jellyfin must not run as root:wheel on Darwin.";
      }
    ];

    nixflix.jellyfin.libraries = mkMerge [
      (mkIf (nixflix.sonarr.enable or false) {
        Shows = {
          collectionType = "tvshows";
          paths = nixflix.sonarr.mediaDirs;
        };
      })
      (mkIf (nixflix.sonarr-anime.enable or false) {
        Anime = {
          collectionType = "tvshows";
          paths = nixflix.sonarr-anime.mediaDirs;
        };
      })
      (mkIf (nixflix.radarr.enable or false) {
        Movies = {
          collectionType = "movies";
          paths = nixflix.radarr.mediaDirs;
        };
      })
      (mkIf (nixflix.lidarr.enable or false) {
        Music = {
          collectionType = "music";
          paths = nixflix.lidarr.mediaDirs;
        };
      })
    ];

    nixflix.jellyfin = {
      user = mkOverride 900 "_nixflix";
      group = mkOverride 900 "_nixflix";
    };

    system.activationScripts.users.text = mkAfter ''
      mkdir -p '${cfg.dataDir}' '${cfg.configDir}' '${cfg.cacheDir}' '${cfg.logDir}' '${cfg.system.metadataPath}' '${cfg.dataDir}/data'
      install -m 640 '${networkXmlFile}' '${cfg.configDir}/network.xml'
      chown -R '${cfg.user}:${cfg.group}' '${cfg.dataDir}' '${cfg.configDir}' '${cfg.cacheDir}' '${cfg.logDir}' '${cfg.system.metadataPath}'
    '';

    launchd.daemons.jellyfin = mkLaunchdService {
      name = "jellyfin";
      label = "org.nixflix.jellyfin";
      serviceConfig = {
        ProgramArguments = [
          "${getExe cfg.package}"
          "--datadir"
          "${cfg.dataDir}"
          "--configdir"
          "${cfg.configDir}"
          "--cachedir"
          "${cfg.cacheDir}"
          "--logdir"
          "${cfg.logDir}"
        ];
        WorkingDirectory = stateDir;
        UserName = cfg.user;
        GroupName = cfg.group;
        StandardOutPath = "${cfg.logDir}/stdout.log";
        StandardErrorPath = "${cfg.logDir}/stderr.log";
        EnvironmentVariables = {
          HOME = stateDir;
          PATH = commonPath;
        };
      };
    };

    launchd.daemons.jellyfin-config = mkIf (cfg.apiKey != null) (mkLaunchdOneshot {
      name = "jellyfin-config";
      standardOutPath = "${cfg.logDir}/jellyfin-config.stdout.log";
      standardErrorPath = "${cfg.logDir}/jellyfin-config.stderr.log";
      workingDirectory = stateDir;
      environment = {
        HOME = stateDir;
        PATH = commonPath;
      };
      script = ''
        ${waitForApiScript}
        (
          ${apiKeyJob.script}
        )
        /bin/launchctl kickstart -k system/org.nixflix.jellyfin
        ${waitForApiScript}
        ${setupWizardJob.script}
        ${systemConfigJob.script}
        ${usersConfigJob.script}
        ${librariesJob.script}
        ${brandingJob.script}
        ${encodingJob.script}
      '';
    });
  };
}
