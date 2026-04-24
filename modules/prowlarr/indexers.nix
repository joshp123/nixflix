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
  indexersJob = import ./mkIndexersJob.nix { inherit config lib pkgs; };
in
{
  imports = [ ./indexersOptions.nix ];

  config.systemd.services."prowlarr-indexers" = mkIf (
    config.nixflix.enable && cfg.enable && cfg.config.apiKey != null
  ) (mkNixosOneshotService indexersJob.mkJob);
}
