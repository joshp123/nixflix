{
  config,
  lib,
  pkgs,
  ...
}:
(import ./mk-arr-service.nix { inherit config lib pkgs; } {
  serviceName = "radarr";
  sharedModule = ../../radarr-shared.nix;
})
