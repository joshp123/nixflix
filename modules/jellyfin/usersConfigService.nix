{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.jellyfin;
  mkNixosOneshotService = import ../backends/nixos/mk-oneshot-service.nix { inherit lib pkgs; };
  mkUsersConfigJob = import ./mkUsersConfigJob.nix { inherit cfg lib pkgs; };
in
{
  config = mkIf (config.nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-users-config = mkNixosOneshotService mkUsersConfigJob;
  };
}
