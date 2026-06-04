{ serviceName }:
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  cfg = config.nixflix.${serviceName};
  inherit (import ./utils.nix { inherit lib pkgs serviceName; })
    usesMediaDirs
    capitalizedName
    ;
  configureCustomFormats = ./scripts/configure-custom-formats.sh;
in
{
  options.nixflix.${serviceName}.config = optionalAttrs usesMediaDirs {
    customFormats = mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [ ];
      description = ''
        Custom formats to create or update via the API /customformat endpoint.
        Each custom format may include a `scores` attribute mapping quality profile
        names to scores. Existing custom formats not listed here are left alone.
      '';
    };
  };

  config =
    mkIf
      (
        usesMediaDirs
        && config.nixflix.enable
        && cfg.enable
        && cfg.config.apiKey != null
        && cfg.config.customFormats != [ ]
      )
      {
        systemd.services."${serviceName}-customformats" =
          let
            qualityProfileDeps = optional (
              cfg.config.qualityProfiles != [ ]
            ) "${serviceName}-qualityprofiles.service";
          in
          {
            description = "Configure ${capitalizedName} custom formats via API";
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
              let
                baseUrl = "http://${cfg.connectionAddress}:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}";
                formatsFile = pkgs.writeText "${serviceName}-custom-formats.json" (
                  builtins.toJSON cfg.config.customFormats
                );
              in
              "ARR_API_KEY=${secrets.toShellValue cfg.config.apiKey} "
              + "${pkgs.bash}/bin/bash ${configureCustomFormats} "
              + "${escapeShellArg capitalizedName} ${escapeShellArg baseUrl} ${formatsFile}";
          };
      };
}
