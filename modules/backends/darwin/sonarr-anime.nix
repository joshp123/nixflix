{
  config,
  lib,
  pkgs,
  ...
}:
(import ./mk-arr-service.nix { inherit config lib pkgs; } {
  serviceName = "sonarr-anime";
  sharedModule = ../../sonarr-anime-shared.nix;
})
