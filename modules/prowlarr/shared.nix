{
  config,
  lib,
  ...
}:
with lib;
let
  inherit (config) nixflix;

  arrServices =
    optional (nixflix.lidarr.enable or false) "lidarr"
    ++ optional (nixflix.radarr.enable or false) "radarr"
    ++ optional (nixflix.sonarr.enable or false) "sonarr"
    ++ optional (nixflix.sonarr-anime.enable or false) "sonarr-anime";

  mkDefaultApplication =
    serviceName:
    let
      serviceConfig = nixflix.${serviceName}.config;
      displayName = concatMapStringsSep " " (
        word: toUpper (builtins.substring 0 1 word) + builtins.substring 1 (-1) word
      ) (splitString "-" serviceName);
      serviceBase = builtins.elemAt (splitString "-" serviceName) 0;
      implementationName = toUpper (substring 0 1 serviceBase) + substring 1 (-1) serviceBase;
      baseUrl = "http://127.0.0.1:${toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}";
      prowlarrUrl = "http://127.0.0.1:${toString nixflix.prowlarr.config.hostConfig.port}${nixflix.prowlarr.config.hostConfig.urlBase}";
    in
    mkIf (nixflix.${serviceName}.enable or false) {
      name = displayName;
      inherit implementationName;
      apiKey = mkDefault serviceConfig.apiKey;
      baseUrl = mkDefault baseUrl;
      prowlarrUrl = mkDefault prowlarrUrl;
    };

  defaultApplications = filter (app: app != { }) (map mkDefaultApplication arrServices);
in
{
  options.nixflix.prowlarr.config.applications = mkOption {
    type = types.listOf (
      types.submodule {
        freeformType = types.attrsOf types.anything;
        options = {
          name = mkOption {
            type = types.str;
            description = "User-defined name for the application instance";
          };
          implementationName = mkOption {
            type = types.enum [
              "LazyLibrarian"
              "Lidarr"
              "Mylar"
              "Readarr"
              "Radarr"
              "Sonarr"
              "Whisparr"
            ];
            description = "Type of application to configure (matches schema implementationName)";
          };
          apiKey = (import ../../lib/secrets { inherit lib; }).mkSecretOption {
            description = "Path to file containing the API key for the application";
          };
        };
      }
    );
    default = [ ];
    defaultText = literalExpression ''
      # Automatically configured for enabled arr services (Sonarr, Radarr, Lidarr)
      # Each enabled service gets an application entry with computed baseUrl and prowlarrUrl
      # based on local service ports
    '';
    description = ''
      List of applications to configure in Prowlarr.
      Any additional attributes beyond name, implementationName, and apiKey
      will be applied as field values to the application schema.
    '';
  };

  config.nixflix.prowlarr = {
    config = {
      apiVersion = lib.mkDefault "v1";
      hostConfig = {
        port = lib.mkDefault 9696;
        branch = lib.mkDefault "master";
      };
      applications = lib.mkDefault defaultApplications;
    };
  };
}
