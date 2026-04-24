{
  config,
  lib,
  pkgs,
  ...
}:
(import ./mk-arr-service.nix { inherit config lib pkgs; } {
  serviceName = "sonarr";
  sharedModule = ../../sonarr-shared.nix;
})
