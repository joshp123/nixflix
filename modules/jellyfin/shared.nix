{
  config,
  lib,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = config.nixflix.jellyfin;
in
{
  imports = [
    ./options

    ./apiKeyService.nix
    ./brandingService.nix
    ./encodingService.nix
    ./librariesService.nix
    ./setupWizardService.nix
    ./systemConfigService.nix
    ./usersConfigService.nix
  ];

  config = mkIf (nixflix.enable && cfg.enable) {
    nixflix.jellyfin.libraries = mkMerge [
      (mkIf (nixflix.sonarr.enable or false) {
        Shows = {
          collectionType = "tvshows";
          paths = nixflix.sonarr.mediaDirs;
        };
      })
      (mkIf (nixflix.sonarr-anime.enable or false) {
        Anime = {
          collectionType = "tvshows";
          paths = nixflix.sonarr-anime.mediaDirs;
        };
      })
      (mkIf (nixflix.radarr.enable or false) {
        Movies = {
          collectionType = "movies";
          paths = nixflix.radarr.mediaDirs;
        };
      })
      (mkIf (nixflix.lidarr.enable or false) {
        Music = {
          collectionType = "music";
          paths = nixflix.lidarr.mediaDirs;
        };
      })
    ];

    assertions = [
      {
        assertion = cfg.vpn.enable -> (config.nixflix.mullvad.enable or false);
        message = "Cannot enable VPN routing for Jellyfin (nixflix.jellyfin.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
      }
      {
        assertion = any (user: user.policy.isAdministrator) (attrValues cfg.users);
        message = "At least one Jellyfin user must have policy.isAdministrator = true.";
      }
      {
        assertion = cfg.system.cacheSize >= 3;
        message = "nixflix.jellyfin.system.cacheSize must be at least 3 due to Jellyfin's internal caching implementation (got ${toString cfg.system.cacheSize}).";
      }
    ];
  };
}
