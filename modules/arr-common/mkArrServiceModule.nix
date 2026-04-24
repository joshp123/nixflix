{
  config,
  lib,
  pkgs,
  ...
}:
serviceName: {
  imports = [
    (import ./mkArrBaseModule.nix { inherit config lib pkgs; } serviceName)
    (import ../backends/nixos/mk-arr-service.nix { inherit config lib pkgs; } serviceName)
  ];
}
