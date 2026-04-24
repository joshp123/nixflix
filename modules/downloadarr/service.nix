{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.downloadarr;
  mkNixosOneshotService = import ../backends/nixos/mk-oneshot-service.nix { inherit lib pkgs; };
  allClients = filter (c: c.enable) (
    builtins.attrValues (
      builtins.removeAttrs cfg [
        "extraClients"
        "enable"
      ]
    )
    ++ cfg.extraClients
  );

  arrServices = [
    "radarr"
    "sonarr"
    "sonarr-anime"
    "lidarr"
    "prowlarr"
  ];
  mkDownloadClientsJob = import ./mkDownloadClientsJob.nix { inherit config lib pkgs; };

  enabledArrServices = filter (
    serviceName:
    config.nixflix.enable
    && allClients != [ ]
    && (config.nixflix.${serviceName}.enable or false)
    && (config.nixflix.${serviceName}.config.apiKey or null) != null
  ) arrServices;
in
{
  config = mkIf (config.nixflix.enable && cfg.enable && allClients != [ ]) {
    systemd.services = mkMerge (
      map (serviceName: {
        "${serviceName}-downloadclients" = mkNixosOneshotService (mkDownloadClientsJob serviceName).mkJob;
      }) enabledArrServices
    );
  };
}
