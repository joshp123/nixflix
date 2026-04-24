{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.prowlarr;
  mkNixosOneshotService = import ../backends/nixos/mk-oneshot-service.nix { inherit lib pkgs; };
  applicationsJob = import ./mkApplicationsJob.nix { inherit config lib pkgs; };
in
{
  config.systemd.services."prowlarr-applications" = mkIf (
    config.nixflix.enable && cfg.enable && cfg.config.apiKey != null
  ) (mkNixosOneshotService applicationsJob.mkJob);
}
