{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  bazarr = import ./bazarr.nix;
  qbittorrent = import ./qbittorrent.nix;
  inherit (config.nixflix) globals;
  cfg = config.nixflix;
  mountGated = cfg.serviceDependencies != [ ];
  managedDirs = [
    {
      path = cfg.mediaDir;
      mode = "0774";
      inherit (globals.libraryOwner) user group;
    }
    {
      path = cfg.downloadsDir;
      mode = "0774";
      inherit (globals.libraryOwner) user group;
    }
  ];
  # For mounted NAS paths, only create missing directories. The NAS ACL owns
  # permissions; client-side chown/chmod can fail on exports like Synology NFS.
  createManagedDir = dir: "${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg (toString dir.path)}";
in
{
  imports = [
    bazarr
    qbittorrent
  ];

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
    }
    // optionalAttrs (!mountGated) (
      listToAttrs (
        map (dir: {
          name = toString dir.path;
          value.d = {
            inherit (dir) mode user group;
          };
        }) managedDirs
      )
    );

    systemd.services.nixflix-setup-dirs = {
      description = "Create tmp files";
      after = [ "systemd-tmpfiles-setup.service" ] ++ cfg.serviceDependencies;
      requires = [ "systemd-tmpfiles-setup.service" ] ++ cfg.serviceDependencies;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${optionalString mountGated (concatMapStringsSep "\n" createManagedDir managedDirs)}
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
