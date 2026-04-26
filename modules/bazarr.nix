{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../lib/secrets { inherit lib; };
  cfg = config.nixflix.bazarr;
in
{
  options.nixflix.bazarr = {
    enable = mkEnableOption "Bazarr";
    package = mkPackageOption pkgs "bazarr" { };

    user = mkOption {
      type = types.str;
      default = "bazarr";
      description = "User under which Bazarr runs.";
    };

    group = mkOption {
      type = types.str;
      default = "bazarr";
      description = "Group under which Bazarr runs.";
    };

    config = {
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Bazarr bind address.";
      };

      port = mkOption {
        type = types.port;
        default = 6767;
        description = "Bazarr web port.";
      };

      urlBase = mkOption {
        type = types.str;
        default = "/bazarr";
        description = "Bazarr reverse-proxy URL base.";
      };

      sonarrApiKey = secrets.mkSecretOption {
        nullable = true;
        default = null;
        description = "Sonarr API key used by Bazarr.";
      };

      radarrApiKey = secrets.mkSecretOption {
        nullable = true;
        default = null;
        description = "Radarr API key used by Bazarr.";
      };

      opensubtitlescom = {
        username = secrets.mkSecretOption {
          nullable = true;
          default = null;
          description = "OpenSubtitles.com username.";
        };

        password = secrets.mkSecretOption {
          nullable = true;
          default = null;
          description = "OpenSubtitles.com password.";
        };
      };
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    nixflix.bazarr.config = {
      sonarrApiKey = mkDefault config.nixflix.sonarr.config.apiKey;
      radarrApiKey = mkDefault config.nixflix.radarr.config.apiKey;
    };

    assertions = [
      {
        assertion = config.nixflix.sonarr.enable && cfg.config.sonarrApiKey != null;
        message = "nixflix.bazarr requires nixflix.sonarr with an API key.";
      }
      {
        assertion = config.nixflix.radarr.enable && cfg.config.radarrApiKey != null;
        message = "nixflix.bazarr requires nixflix.radarr with an API key.";
      }
      {
        assertion =
          (cfg.config.opensubtitlescom.username == null) == (cfg.config.opensubtitlescom.password == null);
        message = "nixflix.bazarr.config.opensubtitlescom requires both username and password, or neither.";
      }
    ];
  };
}
