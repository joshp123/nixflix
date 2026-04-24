{
  lib,
  ...
}:
with lib;
{
  options.nixflix = {
    enable = mkEnableOption "Nixflix";

    serviceDependencies = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "unlock-raid.service"
        "tailscale.service"
      ];
      description = ''
        List of systemd services that nixflix services should wait for before starting.
        Useful for mounting encrypted drives, starting VPNs, or other prerequisites.
      '';
    };

    theme = {
      enable = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Enables themeing via [theme.park](https://docs.theme-park.dev/).
          Requires `nixflix.nginx.enable = true;` for all services except Jellyfin.
        '';
      };
      name = mkOption {
        type = types.str;
        default = "overseerr";
        description = ''
          The name of any official theme or community theme supported by theme.park.

          - [Official Themes](https://docs.theme-park.dev/theme-options/)
          - [Community Themes](https://docs.theme-park.dev/community-themes/)
        '';
      };
    };

    nginx = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable nginx reverse proxy for all services";
      };

      domain = mkOption {
        type = types.str;
        default = "nixflix";
        example = "internal";
        description = "Base domain for subdomain-based reverse proxy routing. Each service is accessible at `<subdomain>.<domain>`.";
      };

      addHostsEntries = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to add `networking.hosts` entries mapping service subdomains to `127.0.0.1`.

          Enable if you don't have a separate DNS setup.
        '';
      };

      forceSSL = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = "Whether to force SSL.";
      };

      enableACME = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether to enable `useACMEHost` in virtual hosts. Uses `nixflix.nginx.domain` as ACME host.

          You have to configure `security.acme.certs.$${nixflix.nginx.domain}` in order to use this.
        '';
      };
    };

    mediaUsers = mkOption {
      type = with types; listOf str;
      default = [ ];
      example = [ "user" ];
      description = ''
        Extra users to add to the media group.
      '';
    };

    mediaDir = mkOption {
      type = types.path;
      default = "/data/media";
      example = "/data/media";
      description = ''
        The location of the media directory for the services.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        > mediaDir = /home/user/data
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    downloadsDir = mkOption {
      type = types.path;
      default = "/data/downloads";
      example = "/data/downloads";
      description = ''
        The location of the downloads directory for download clients.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        > downloadsDir = /home/user/downloads
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/data/.state";
      example = "/data/.state";
      description = ''
        The location of the state directory for the services.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        > stateDir = /home/user/data/.state
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    runtime = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      internal = true;
      description = "Internal runtime metadata derived by backend-specific service modules.";
    };
  };
}
