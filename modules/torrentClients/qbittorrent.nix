{
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  cfg = config.nixflix.torrentClients.qbittorrent;
in
{
  options.nixflix.torrentClients.qbittorrent = mkOption {
    type = types.submodule {
      freeformType = types.attrsOf types.anything;
      options = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to enable qBittorrent usenet downloader.

            Uses all of the same options as [nixpkgs qBittorent](https://search.nixos.org/options?channel=unstable&query=qbittorrent).
          '';
        };

        user = mkOption {
          type = types.str;
          default = "qbittorrent";
          description = "User account under which qbittorrent runs.";
        };

        group = mkOption {
          type = types.str;
          default = config.nixflix.globals.libraryOwner.group;
          description = "Group under which qbittorrent runs.";
        };

        downloadsDir = mkOption {
          type = types.str;
          default = "${config.nixflix.downloadsDir}/torrent";
          defaultText = literalExpression ''"$${config.nixflix.downloadsDir}/torrent"'';
          description = "Base directory for qBittorrent downloads";
        };

        categories = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default =
            let
              getCategory =
                service:
                lib.optionalString (config.nixflix.${service}.enable or false) "${cfg.downloadsDir}/${service}";
            in
            {
              radarr = getCategory "radarr";
              sonarr = getCategory "sonarr";
              sonarr-anime = getCategory "sonarr-anime";
              lidarr = getCategory "lidarr";
              prowlarr = getCategory "prowlarr";
            };
          defaultText = lib.literalExpression ''
            {
              radarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/radarr";
              sonarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/sonarr";
              sonarr-anime = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/sonarr-anime";
              lidarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/lidarr";
              prowlarr = lib.optionalString (config.nixflix.radarr.enable or false) "${cfg.downloadsDir}/prowlarr";
            }
          '';
          description = "Map of category names to their save paths (relative or absolute).";
          example = {
            prowlarr = "games";
            sonarr = "/mnt/share/movies";
          };
        };

        webuiPort = mkOption {
          type = types.nullOr types.port;
          default = 8282;
          description = "the port passed to qbittorrent via `--webui-port`";
        };

        password = secrets.mkSecretOption {
          description = ''
            The password for qbittorrent. This is for the other services to integrate with qBittorrent.
            Not for setting the password in qBittorrent

            In order to set the password for qBittorrent itself, you will need to configure
            `nixflix.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Password_PBKDF2`. Look at the
            [serverConfig documentation](https://search.nixos.org/options?channel=unstable&query=qbittorrent&show=services.qbittorrent.serverConfig)
            to see how to configure it.
          '';
        };

        subdomain = mkOption {
          type = types.str;
          default = "qbittorrent";
          description = "Subdomain prefix for nginx reverse proxy.";
        };

        serverConfig = {
          BitTorrent.Session = {
            DefaultSavePath = mkOption {
              type = types.str;
              default = "${cfg.downloadsDir}/default";
              defaultText = literalExpression ''"''${config.nixflix.torrentClients.qbittorrent.downloadsDir}/default"'';
              description = "Default save path for downloads without a category.";
            };

            DisableAutoTMMByDefault = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Default Torrent Management Mode. Set to false to enable category save paths.

                `true` = `Manual`, `false` = `Automatic`
              '';
            };
          };

          Preferences.WebUI.Address = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = "Bind address for the WebUI";
          };
        };
      };
    };
    default = { };
  };

  config = mkIf (config.nixflix.enable && cfg != null && cfg.enable) {
    nixflix.runtime.downloadClients.qbittorrent = {
      dependencies = mkDefault [ ];
      host = cfg.serverConfig.Preferences.WebUI.Address;
      port = cfg.webuiPort;
      username = cfg.serverConfig.Preferences.WebUI.Username;
    };
  };
}
