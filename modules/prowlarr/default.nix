{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    (import ../arr-common/mkArrServiceModule.nix { inherit config lib pkgs; } "prowlarr")
    ./shared.nix
    ./applications.nix
    ./indexers.nix
    ./indexerProxies.nix
    ./tags.nix
  ];
}
