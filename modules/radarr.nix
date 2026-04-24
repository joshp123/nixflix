{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    (import ./arr-common/mkArrServiceModule.nix { inherit config lib pkgs; } "radarr")
    ./radarr-shared.nix
  ];
}
