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
  mkNixosOneshotService = import ../backends/nixos/mk-oneshot-service.nix { inherit lib pkgs; };
  mkSystemConfigJob = import ./mkSystemConfigJob.nix { inherit cfg lib pkgs; };
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-system-config = mkNixosOneshotService mkSystemConfigJob;
  };
}
