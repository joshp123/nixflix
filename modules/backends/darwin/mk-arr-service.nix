{
  config,
  lib,
  pkgs,
  ...
}:
{
  serviceName,
  sharedModule,
  extraModules ? [ ],
  extraConvergenceScripts ? [ ],
}:
with lib;
let
  baseModule = import ../../arr-common/mkArrBaseModule.nix { inherit config lib pkgs; } serviceName;
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
  mkWaitForApiScript = import ../../arr-common/mkWaitForApiScript.nix { inherit lib pkgs; };
  mkDownloadClientsJob = import ../../downloadarr/mkDownloadClientsJob.nix {
    inherit config lib pkgs;
  };
  mkLaunchdOneshot = import ./mk-launchd-oneshot.nix { inherit pkgs; };
  mkServarrSettingsEnvVars = import ../../arr-common/mkServarrSettingsEnvVars.nix { inherit lib; };
  secrets = import ../../../lib/secrets { inherit lib; };

  cfg = config.nixflix.${serviceName};
  stateDir = "${config.nixflix.stateDir}/${serviceName}";
  logDir = "${stateDir}/logs";
  serviceBase = builtins.elemAt (splitString "-" serviceName) 0;
  apiKeyEnvVar = "${toUpper serviceBase}__AUTH__APIKEY";
  commonPath = "${
    lib.makeBinPath [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.curl
      pkgs.jq
    ]
  }:/usr/bin:/bin:/usr/sbin:/sbin";
  usesMediaDirs = serviceName != "prowlarr";

  downloadarrCfg = config.nixflix.downloadarr;
  allDownloadClients = filter (client: client.enable or false) (
    builtins.attrValues (
      builtins.removeAttrs downloadarrCfg [
        "extraClients"
        "enable"
      ]
    )
    ++ downloadarrCfg.extraClients
  );
  servicesWithDownloadClients = [
    "radarr"
    "sonarr"
    "sonarr-anime"
    "prowlarr"
  ];

  waitForApi = mkWaitForApiScript serviceName cfg.config;
  waitForUrl = label: url: ''
    for _attempt in $(seq 1 60); do
      if ${pkgs.curl}/bin/curl --retry 0 --connect-timeout 2 --max-time 5 -fsS -o /dev/null '${url}'; then
        break
      fi
      if [ "$_attempt" -eq 60 ]; then
        echo "Timed out waiting for ${label} at ${url}" >&2
        exit 1
      fi
      sleep 2
    done
  '';

  hasHostConfig = cfg.config.apiKey != null && cfg.config.hostConfig.password != null;
  hasRootFolders = usesMediaDirs && cfg.config.apiKey != null && cfg.config.rootFolders != [ ];
  hasDelayProfiles = usesMediaDirs && cfg.config.apiKey != null;
  hasDownloadClients =
    cfg.config.apiKey != null
    && downloadarrCfg.enable
    && allDownloadClients != [ ]
    && elem serviceName servicesWithDownloadClients;
  hasConvergence =
    hasHostConfig
    || hasRootFolders
    || hasDelayProfiles
    || hasDownloadClients
    || extraConvergenceScripts != [ ];

  launchScript = pkgs.writeShellScript "${serviceName}-launch" ''
    set -eu

    ${optionalString (cfg.config.apiKey != null) ''
      api_key=${secrets.toShellValue cfg.config.apiKey}
      export ${apiKeyEnvVar}="$api_key"
    ''}

    exec ${getExe cfg.package} -nobrowser -data='${stateDir}'
  '';

  hostConfigScript = optionalString hasHostConfig (
    let
      job = hostConfig.mkJob cfg.config;
    in
    ''
      ${waitForApi}
      ${job.script}
      ${waitForApi}
    ''
  );

  rootFoldersScript = optionalString hasRootFolders (
    let
      job = rootFolders.mkJob cfg.config;
    in
    ''
      ${waitForApi}
      ${job.script}
    ''
  );

  delayProfilesScript = optionalString hasDelayProfiles (
    let
      job = delayProfiles.mkJob cfg.config;
    in
    ''
      ${waitForApi}
      ${job.script}
    ''
  );

  downloadClientsScript = optionalString hasDownloadClients (
    let
      job = (mkDownloadClientsJob serviceName).mkJob;
    in
    ''
      ${waitForApi}
      ${waitForUrl "qBittorrent" "http://127.0.0.1:${toString config.nixflix.runtime.downloadClients.qbittorrent.port}/"}
      ${job.script}
    ''
  );

  serviceSpec = {
    name = serviceName;
    argv = [ "${launchScript}" ];
    cwd = stateDir;
    stdout = "${logDir}/stdout.log";
    stderr = "${logDir}/stderr.log";
    env = (mkServarrSettingsEnvVars (toUpper serviceBase) cfg.settings) // {
      HOME = stateDir;
      PATH = commonPath;
    };
  };

  configOneshot = mkLaunchdOneshot {
    name = "${serviceName}-config";
    standardOutPath = "${logDir}/${serviceName}-config.stdout.log";
    standardErrorPath = "${logDir}/${serviceName}-config.stderr.log";
    workingDirectory = stateDir;
    environment = {
      HOME = stateDir;
      PATH = commonPath;
    };
    script = concatStringsSep "\n" (
      [
        hostConfigScript
        rootFoldersScript
        delayProfilesScript
        downloadClientsScript
      ]
      ++ extraConvergenceScripts
    );
  };

  configSpec = {
    name = "${serviceName}-config";
    argv = configOneshot.serviceConfig.ProgramArguments;
    cwd = configOneshot.serviceConfig.WorkingDirectory;
    stdout = configOneshot.serviceConfig.StandardOutPath;
    stderr = configOneshot.serviceConfig.StandardErrorPath;
    env = configOneshot.serviceConfig.EnvironmentVariables;
  };
in
{
  imports = [
    baseModule
    sharedModule
  ]
  ++ extraModules;

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = !cfg.openFirewall;
        message = "nixflix.${serviceName}.openFirewall is not implemented on Darwin yet.";
      }
      {
        assertion = !cfg.vpn.enable;
        message = "nixflix.${serviceName}.vpn.enable is not implemented on Darwin yet.";
      }
      {
        assertion = !config.nixflix.nginx.enable;
        message = "nixflix.nginx is not implemented on Darwin yet.";
      }
      {
        assertion = !(config.nixflix.postgres.enable or false);
        message = "nixflix.postgres is not implemented on Darwin yet.";
      }
      {
        assertion = cfg.user != "root" && cfg.group != "wheel";
        message = "nixflix.${serviceName} must not run as root:wheel on Darwin.";
      }
    ];

    nixflix.${serviceName} = {
      user = mkOverride 900 "nixflix";
      group = mkOverride 900 "staff";
      config.hostConfig.bindAddress = mkDefault "*";
    };

    system.activationScripts.users.text = mkAfter ''
      mkdir -p '${stateDir}' '${logDir}'
      ${concatMapStringsSep "\n" (path: "mkdir -p '${toString path}'") (cfg.mediaDirs or [ ])}
      chown -R '${cfg.user}:${cfg.group}' '${stateDir}'
    '';

    nixflix.runtime.darwinSupervisorManifest.services = [ serviceSpec ];
    nixflix.runtime.darwinSupervisorManifest.jobs = mkIf hasConvergence [ configSpec ];
  };
}
