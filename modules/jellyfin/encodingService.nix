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
  mkEncodingJob = import ./mkEncodingJob.nix { inherit cfg lib pkgs; };
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.tmpfiles.settings."10-jellyfin" = mkIf (cfg.encoding.transcodingTempPath != "") {
      "${cfg.encoding.transcodingTempPath}".d = {
        inherit (cfg) user group;
        mode = "0755";
      };
    };

    systemd.services.jellyfin-encoding-config = mkNixosOneshotService mkEncodingJob;
  };
}
