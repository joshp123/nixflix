{
  config,
  lib,
  ...
}:
with lib;
{
  imports = [
    ../../shared/core.nix
    ../../globals.nix
    ./supervisor.nix
    ./bazarr.nix
    ./downloadarr.nix
    ./jellyfin.nix
    ./prowlarr.nix
    ./qbittorrent.nix
    ./seerr.nix
    ./sonarr.nix
    ./sonarr-anime.nix
    ./radarr.nix
  ];

  config = mkIf config.nixflix.enable {
    assertions = [
      {
        assertion =
          !(config.nixflix.lidarr.enable or false)
          && !(config.nixflix.usenetClients.sabnzbd.enable or false)
          && !(config.nixflix.recyclarr.enable or false)
          && !(config.nixflix.mullvad.enable or false)
          && !(config.nixflix.flaresolverr.enable or false)
          && !config.nixflix.nginx.enable
          && !config.nixflix.theme.enable
          && config.nixflix.mediaUsers == [ ]
          && config.nixflix.serviceDependencies == [ ];
        message = ''
          The Darwin backend is an MVP for Bazarr, Jellyfin, Prowlarr, Seerr, Sonarr, Radarr, qBittorrent, and qBittorrent-based downloadarr wiring.
          Usenet, nginx, themes, mediaUsers, custom serviceDependencies, VPN, Recyclarr, Lidarr, and FlareSolverr are not implemented on Darwin yet.
        '';
      }
    ];

    users.knownUsers = [ "nixflix" ];
    users.users.nixflix = {
      uid = mkDefault 535;
      gid = mkDefault 20;
      description = mkDefault "Nixflix appliance user";
      home = mkDefault config.nixflix.stateDir;
      isHidden = mkDefault true;
      createHome = mkDefault false;
    };

    system.activationScripts.users.text = mkAfter ''
      mkdir -p '${config.nixflix.stateDir}' '${config.nixflix.mediaDir}' '${config.nixflix.downloadsDir}'
      chown 'nixflix:staff' '${config.nixflix.stateDir}'
    '';
  };
}
