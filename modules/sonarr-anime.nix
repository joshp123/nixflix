{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    (import ./arr-common/mkArrServiceModule.nix { inherit config lib pkgs; } "sonarr-anime")
    ./sonarr-anime-shared.nix
  ];
}
