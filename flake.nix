{
  description = "Generic NixOS Jellyfin media server configuration with Arr stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mkdocs-catppuccin = {
      url = "github:ruslanlap/mkdocs-catppuccin";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      darwinSystems = [ "aarch64-darwin" ];
      packageSystems = linuxSystems ++ darwinSystems;

      perSystemFor =
        systems: f:
        lib.genAttrs systems (
          system:
          f rec {
            inherit system lib;
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
              config.allowUnfreePredicate = _: true;
            };
            treefmt = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
          }
        );
    in
    {
      nixosModules.default = import ./modules;
      nixosModules.nixflix = import ./modules;
      darwinModules.default = import ./modules/backends/darwin;
      darwinModules.nixflix = self.darwinModules.default;

      packages = perSystemFor packageSystems (
        {
          system,
          pkgs,
          ...
        }:
        (import ./docs { inherit pkgs inputs; })
        // {
          default = self.packages.${system}.docs;
          seerr = pkgs.callPackage ./pkgs/seerr { };
        }
        // lib.optionalAttrs pkgs.stdenv.isDarwin {
          nixflix-supervisor = pkgs.callPackage ./pkgs/nixflix-supervisor { };
        }
      );

      apps = perSystemFor packageSystems (
        {
          system,
          pkgs,
          ...
        }:
        {
          docs-serve = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "docs-serve" ''
                echo "Starting documentation server from ${self.packages.${system}.docs}"
                ${pkgs.python3}/bin/python3 -m http.server --directory ${self.packages.${system}.docs} 8000
              ''
            );
          };
        }
      );

      formatter = perSystemFor packageSystems ({ treefmt, ... }: treefmt.config.build.wrapper);

      checks =
        perSystemFor linuxSystems (
          {
            treefmt,
            lib,
            pkgs,
            system,
            ...
          }:
          let
            tests = import ./tests {
              inherit system pkgs lib;
              nixosModules = self.nixosModules.default;
              darwinModules = self.darwinModules.default;
            };
          in
          {
            formatting = treefmt.config.build.check self;
            docs-build = self.packages.${system}.docs;
          }
          // tests.vm-tests
          // tests.unit-tests
        )
        // perSystemFor darwinSystems (
          {
            treefmt,
            lib,
            pkgs,
            system,
            ...
          }:
          let
            tests = import ./tests {
              inherit system pkgs lib;
              darwinModules = self.darwinModules.default;
              nixDarwin = inputs.nix-darwin.lib;
            };
          in
          {
            formatting = treefmt.config.build.check self;
            docs-build = self.packages.${system}.docs;
          }
          // tests.darwin-tests
        );

      devShells = perSystemFor packageSystems (
        {
          pkgs,
          treefmt,
          ...
        }:
        {
          default = pkgs.mkShell {
            nativeBuildInputs = [
              treefmt.config.build.wrapper
            ]
            ++ (lib.attrValues treefmt.config.build.programs);

            shellHook = ''
              echo "🎬 Nixflix Development Shell"
              echo ""
              echo "Documentation Commands:"
              echo "  nix build .#docs        - Build documentation"
              echo "  nix run .#docs-serve    - Serve docs"
              echo "  nix fmt                 - Format code"
              echo ""
            '';
          };
        }
      );
    };
}
