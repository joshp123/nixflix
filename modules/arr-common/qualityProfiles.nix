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
  configureQualityProfiles = ./scripts/configure-quality-profiles.sh;
in
{
  options.nixflix.${serviceName}.config = optionalAttrs usesMediaDirs {
    qualityProfiles = mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [ ];
      description = ''
        Quality profiles to create or update via the API /qualityprofile endpoint.
        Profiles are matched by name. Existing profiles not listed here are left alone.
        Set `sourceName` to clone an existing profile and override selected fields.
        Use `allowedQualities` and `disallowedQualities` to converge quality gates by name.
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
        && cfg.config.qualityProfiles != [ ]
      )
      {
        systemd.services."${serviceName}-qualityprofiles" = {
          description = "Configure ${capitalizedName} quality profiles via API";
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
            let
              baseUrl = "http://${cfg.connectionAddress}:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}";
              profilesFile = pkgs.writeText "${serviceName}-quality-profiles.json" (
                builtins.toJSON cfg.config.qualityProfiles
              );
            in
            "ARR_API_KEY=${secrets.toShellValue cfg.config.apiKey} "
            + "${pkgs.bash}/bin/bash ${configureQualityProfiles} "
            + "${escapeShellArg capitalizedName} ${escapeShellArg baseUrl} ${profilesFile}";
        };
      };
}
