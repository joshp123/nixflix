{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  qbittorrent = import ./qbittorrent.nix;
  inherit (config.nixflix) globals;
  cfg = config.nixflix;
in
{
  imports = [ qbittorrent ];

  config = mkIf cfg.enable {
    users.groups.media = {
      gid = globals.gids.media;
      members = cfg.mediaUsers;
    };

    systemd.tmpfiles.settings."10-nixflix" = {
      "${cfg.stateDir}".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "${cfg.mediaDir}".d = {
        mode = "0774";
        inherit (globals.libraryOwner) user;
        inherit (globals.libraryOwner) group;
      };
      "${cfg.downloadsDir}".d = {
        mode = "0774";
        inherit (globals.libraryOwner) user;
        inherit (globals.libraryOwner) group;
      };
    };

    systemd.services.nixflix-setup-dirs = {
      description = "Create tmp files";
      after = [ "systemd-tmpfiles-setup.service" ];
      requires = [ "systemd-tmpfiles-setup.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${pkgs.systemd}/bin/systemd-tmpfiles --create
      '';
    };

    services.nginx = mkIf cfg.nginx.enable {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."_" = {
        default = true;
        extraConfig = ''
          return 444;
        '';
      };
    };
  };
}
