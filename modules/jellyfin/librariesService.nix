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
  mkLibrariesJob = import ./mkLibrariesJob.nix {
    inherit
      config
      cfg
      lib
      pkgs
      ;
  };
in
{
  config = mkIf (nixflix.enable && cfg.enable && cfg.libraries != { }) {
    systemd.services.jellyfin-libraries = mkNixosOneshotService mkLibrariesJob;
  };
}
