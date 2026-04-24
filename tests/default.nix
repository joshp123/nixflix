{
  lib,
  nixosModules ? null,
  darwinModules ? null,
  nixDarwin ? null,
  pkgs ? import <nixpkgs> { inherit system; },
  system ? builtins.currentSystem,
}:
{
  # Import all test modules
  vm-tests =
    if nixosModules == null then
      { }
    else
      import ./vm-tests {
        inherit
          system
          pkgs
          nixosModules
          lib
          ;
      };

  unit-tests =
    if nixosModules == null then { } else import ./unit-tests { inherit system pkgs nixosModules; };

  darwin-tests =
    if darwinModules == null then
      { }
    else
      import ./darwin {
        inherit
          system
          pkgs
          darwinModules
          nixDarwin
          lib
          ;
      };
}
