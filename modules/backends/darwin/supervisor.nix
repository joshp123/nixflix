{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  supervisorPackage = pkgs.callPackage ../../../pkgs/nixflix-supervisor { };
  supervisorUser = "nixflix";
  userHome =
    if config.users.users ? ${supervisorUser} && config.users.users.${supervisorUser}.home != null then
      toString config.users.users.${supervisorUser}.home
    else
      config.nixflix.stateDir;
  logDir = "${userHome}/Library/Logs/nixflix";
  manifest = config.nixflix.runtime.darwinSupervisorManifest;
  manifestFile = pkgs.writeText "nixflix-supervisor-manifest.json" (builtins.toJSON manifest);
  installSupervisor = ./scripts/install-supervisor.sh;
in
{
  options.nixflix.runtime = {
    darwinSupervisorManifest = mkOption {
      internal = true;
      type = types.submodule {
        options = {
          version = mkOption {
            type = types.int;
            default = 1;
          };
          logDir = mkOption {
            type = types.str;
            default = logDir;
          };
          selfTest = mkOption {
            type = types.nullOr (types.attrsOf types.str);
            default = null;
          };
          services = mkOption {
            type = types.listOf (types.attrsOf types.anything);
            default = [ ];
          };
          jobs = mkOption {
            type = types.listOf (types.attrsOf types.anything);
            default = [ ];
          };
        };
      };
      default = { };
      description = "Internal command manifest consumed by NixflixSupervisor.app on Darwin.";
    };

    darwinSupervisorManifestFile = mkOption {
      internal = true;
      type = types.path;
      default = manifestFile;
      description = "Generated NixflixSupervisor.app manifest.";
    };
  };

  config = mkIf config.nixflix.enable {
    nixflix.runtime.darwinSupervisorManifest.selfTest = mkDefault {
      directWritePath = "${config.nixflix.downloadsDir}/.nixflix-supervisor-direct-write";
      childWritePath = "${config.nixflix.downloadsDir}/.nixflix-supervisor-child-write";
      hardlinkSourcePath = "${config.nixflix.downloadsDir}/.nixflix-supervisor-hardlink-source";
      hardlinkTargetPath = "${config.nixflix.mediaDir}/.nixflix-supervisor-hardlink-target";
    };

    environment.systemPackages = [ supervisorPackage ];

    system.activationScripts.postActivation.text = mkAfter ''
      ${installSupervisor} ${
        escapeShellArgs [
          supervisorUser
          userHome
          logDir
          "${supervisorPackage}/Applications/NixflixSupervisor.app"
          "${manifestFile}"
        ]
      }
    '';
  };
}
