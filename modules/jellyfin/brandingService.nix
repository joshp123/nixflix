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
  mkBrandingJob = import ./mkBrandingJob.nix { inherit cfg lib pkgs; };
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.jellyfin-branding-config = mkNixosOneshotService mkBrandingJob;
  };
}
