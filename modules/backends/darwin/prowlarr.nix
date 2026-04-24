{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.prowlarr;
  applicationsJob = import ../../prowlarr/mkApplicationsJob.nix { inherit config lib pkgs; };
  tagsJob = import ../../prowlarr/mkTagsJob.nix { inherit config lib pkgs; };
  indexersJob = import ../../prowlarr/mkIndexersJob.nix { inherit config lib pkgs; };
  mkWaitForApiScript = import ../../arr-common/mkWaitForApiScript.nix { inherit lib pkgs; };
  waitForApi = serviceName: "${mkWaitForApiScript serviceName config.nixflix.${serviceName}.config}";
in
{
  imports = [
    (import ./mk-arr-service.nix { inherit config lib pkgs; } {
      serviceName = "prowlarr";
      sharedModule = ../../prowlarr/shared.nix;
      extraModules = [ ../../prowlarr/indexersOptions.nix ];
      extraConvergenceScripts = optionals (cfg.config.apiKey != null) [
        ''
          ${waitForApi "prowlarr"}
          ${tagsJob.mkJob.script}
        ''
        ''
          ${waitForApi "prowlarr"}
          ${optionalString config.nixflix.radarr.enable (waitForApi "radarr")}
          ${optionalString config.nixflix.sonarr.enable (waitForApi "sonarr")}
          ${optionalString config.nixflix.sonarr-anime.enable (waitForApi "sonarr-anime")}
          ${applicationsJob.mkJob.script}
        ''
        ''
          ${waitForApi "prowlarr"}
          ${indexersJob.mkJob.script}
        ''
      ];
    })
  ];
}
