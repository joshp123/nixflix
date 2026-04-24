{
  config,
  lib,
  pkgs,
  ...
}:
serviceName:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  cfg = config.nixflix.${serviceName};

  hostConfig = import ./hostConfig.nix { inherit lib pkgs serviceName; };
  rootFolders = import ./rootFolders.nix {
    inherit
      config
      lib
      pkgs
      serviceName
      ;
  };
  delayProfiles = import ./delayProfiles.nix { inherit lib pkgs serviceName; };
  capitalizedName = toUpper (substring 0 1 serviceName) + substring 1 (-1) serviceName;
  usesMediaDirs = !(elem serviceName [ "prowlarr" ]);
  serviceBase = builtins.elemAt (splitString "-" serviceName) 0;
in
{
  options.nixflix.${serviceName} = {
    enable = mkEnableOption "${capitalizedName}";
    package = mkPackageOption pkgs serviceBase { };

    vpn = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to route ${capitalizedName} traffic through the VPN.
          When false (default), ${capitalizedName} bypasses the VPN to prevent Cloudflare and image provider blocks.
          When true, ${capitalizedName} routes through the VPN (requires `nixflix.mullvad.enable = true`).
        '';
      };
    };

    user = mkOption {
      type = types.str;
      default = serviceName;
      description = "User under which the service runs";
    };

    group = mkOption {
      type = types.str;
      default = serviceName;
      description = "Group under which the service runs";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open ports in the firewall for the Radarr web interface.";
    };

    subdomain = mkOption {
      type = types.str;
      default = serviceName;
      description = "Subdomain prefix for nginx reverse proxy. Service accessible at `<subdomain>.<domain>`.";
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = (pkgs.formats.ini { }).type;
        options = {
          app = {
            instanceName = mkOption {
              type = types.str;
              description = "Name of the instance";
              default = capitalizedName;
            };
          };
          update = {
            mechanism = mkOption {
              type =
                with types;
                nullOr (enum [
                  "external"
                  "builtIn"
                  "script"
                ]);
              description = "which update mechanism to use";
              default = "external";
            };
            automatically = mkOption {
              type = types.bool;
              description = "Automatically download and install updates.";
              default = false;
            };
          };
          server = {
            port = mkOption {
              type = types.port;
              description = "Port Number";
            };
          };
          log = {
            analyticsEnabled = mkOption {
              type = types.bool;
              description = "Send Anonymous Usage Data";
              default = false;
            };
          };
        };
      };
      defaultText = literalExpression ''
        {
          auth = {
            required = "Enabled";
            method = "Forms";
          };
          server = {
            inherit (config.nixflix.${serviceName}.config.hostConfig) port urlBase;
          };
        }
      '';
      example = options.literalExpression ''
        {
          update.mechanism = "internal";
          server = {
            urlbase = "localhost";
            port = 8989;
            bindaddress = "*";
          };
        }
      '';
      default = { };
      description = ''
        Attribute set of arbitrary config options.
        Please consult the documentation at the [wiki](https://wiki.servarr.com/useful-tools#using-environment-variables-for-config).

        !!! warning

            This configuration is stored in the world-readable Nix store!
            Don't put secrets here!
      '';
    };

    config = mkOption {
      type = types.submodule {
        options = {
          apiVersion = mkOption {
            type = types.str;
            default = "v3";
            description = "Current version of the API of the service";
          };

          apiKey = secrets.mkSecretOption {
            default = null;
            description = "API key for ${capitalizedName}.";
          };
        }
        // {
          hostConfig = hostConfig.options;
        }
        // optionalAttrs usesMediaDirs {
          rootFolders = rootFolders.options;
          delayProfiles = delayProfiles.options;
        };
      };
      default = { };
      description = "${capitalizedName} configuration options that will be set via the API.";
    };
  }
  // optionalAttrs usesMediaDirs {
    mediaDirs = mkOption {
      type = types.listOf types.path;
      default = [ ];
      defaultText = literalExpression ''[config.nixflix.mediaDir + "/<media-type>"]'';
      description = "List of media directories to create and manage";
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> (config.nixflix.mullvad.enable or false);
        message = "Cannot enable VPN routing for ${capitalizedName} (config.nixflix.${serviceName}.vpn.enable = true) when Mullvad VPN is disabled. Please set nixflix.mullvad.enable = true.";
      }
    ];

    nixflix.${serviceName} = {
      settings = {
        auth = {
          required = "Enabled";
          method = "Forms";
        };
        server = { inherit (cfg.config.hostConfig) port urlBase; };
      };
      config = {
        apiKey = mkDefault null;
        hostConfig = {
          username = mkDefault serviceBase;
          password = mkDefault null;
          instanceName = mkDefault capitalizedName;
        };
      };
    };
  };
}
