{
  lib,
  ...
}:
with lib;
{
  options.nixflix.seerr.plex = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Configure Seerr to use a Plex server.";
    };

    hostname = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Plex server hostname or IP address.";
    };

    port = mkOption {
      type = types.port;
      default = 32400;
      description = "Plex server port.";
    };

    useSsl = mkOption {
      type = types.bool;
      default = false;
      description = "Use HTTPS when Seerr connects to Plex.";
    };

    webAppUrl = mkOption {
      type = types.str;
      default = "";
      description = "Optional Plex web app URL stored in Seerr.";
    };

    enableAllLibraries = mkOption {
      type = types.bool;
      default = true;
      description = "Enable all movie and TV libraries discovered from Plex.";
    };

    libraryNames = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Library names to enable when enableAllLibraries is false.";
    };
  };
}
