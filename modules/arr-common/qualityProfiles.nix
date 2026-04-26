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
  configureQualityProfiles = ./scripts/configure-quality-profiles.sh;
in
{
  options = mkOption {
    type = types.listOf (types.attrsOf types.anything);
    default = [ ];
    description = ''
      List of quality profiles to create or update via the API /qualityprofile endpoint.
      Profiles are matched by name. Existing profiles not listed here are left alone.
      Set `sourceName` to clone an existing profile from the service and override only selected fields.
    '';
  };

  mkJob =
    serviceConfig:
    let
      baseUrl = "http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}";
      profilesFile = pkgs.writeText "${serviceName}-quality-profiles.json" (
        builtins.toJSON serviceConfig.qualityProfiles
      );
    in
    {
      description = "Configure ${serviceName} quality profiles via API";
      after = [ "${serviceName}-config.service" ];
      requires = [ "${serviceName}-config.service" ];
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
        + "${pkgs.bash}/bin/bash ${configureQualityProfiles} "
        + "${escapeShellArg capitalizedName} ${escapeShellArg baseUrl} ${profilesFile}";
    };
}
