{
  lib,
  stdenv,
  swift,
  swiftpm,
}:

stdenv.mkDerivation {
  pname = "nixflix-supervisor";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    swift
    swiftpm
  ];

  buildPhase = builtins.readFile ./build-phase.sh;

  installPhase = builtins.readFile ./install-phase.sh;

  meta = {
    description = "macOS TCC/runtime adapter for Nixflix";
    platforms = lib.platforms.darwin;
  };
}
