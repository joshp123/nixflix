{
  lib,
  pkgs,
  serviceName,
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  capitalizedName =
    lib.toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
  configureCustomFormats = ./scripts/configure-custom-formats.sh;
in
{
  options = mkOption {
    type = types.listOf (types.attrsOf types.anything);
    default = [ ];
    description = ''
      List of custom formats to create or update via the API /customformat endpoint.
      Each custom format may include a `scores` attribute mapping quality profile names to scores.
      Existing custom formats not listed here are left alone.
    '';
  };

  mkJob =
    serviceConfig:
    let
      baseUrl = "http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}";
      formatsFile = pkgs.writeText "${serviceName}-custom-formats.json" (
        builtins.toJSON serviceConfig.customFormats
      );
      qualityProfileDeps = optional (
        serviceConfig.qualityProfiles != [ ]
      ) "${serviceName}-qualityprofiles.service";
    in
    {
      description = "Configure ${serviceName} custom formats via API";
      after = [ "${serviceName}-config.service" ] ++ qualityProfileDeps;
      requires = [ "${serviceName}-config.service" ] ++ qualityProfileDeps;
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script =
        "ARR_API_KEY=${secrets.toShellValue serviceConfig.apiKey} "
        + "${pkgs.bash}/bin/bash ${configureCustomFormats} "
        + "${escapeShellArg capitalizedName} ${escapeShellArg baseUrl} ${formatsFile}";
    };
}
