{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.nixflix.downloadarr;
in
{
  imports = [ ../../downloadarr/options.nix ];

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = !(config.nixflix.lidarr.enable or false);
        message = "nixflix.downloadarr on Darwin does not support lidarr yet.";
      }
      {
        assertion =
          !(cfg.sabnzbd.enable or false)
          && !(cfg.rtorrent.enable or false)
          && !(cfg.deluge.enable or false)
          && !(cfg.transmission.enable or false)
          && cfg.extraClients == [ ];
        message = "nixflix.downloadarr on Darwin MVP supports only the built-in qBittorrent client.";
      }
    ];
  };
}
