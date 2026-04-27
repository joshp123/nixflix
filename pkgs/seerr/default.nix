{
  lib,
  fetchFromGitHub,
  fetchPnpmDeps,
  makeWrapper,
  node-gyp,
  nodejs_22,
  pkg-config,
  pnpmConfigHook,
  pnpm_10,
  python3,
  python3Packages,
  replaceVars,
  sqlite,
  stdenv,
  xcbuild,
}:

let
  nodejs = nodejs_22;
  pnpm = pnpm_10.override { inherit nodejs; };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "seerr";
  version = "3.2.0";

  src = fetchFromGitHub {
    owner = "seerr-team";
    repo = "seerr";
    tag = "v${finalAttrs.version}";
    hash = "sha256-rZ4o0ccfQjZBzWItEEFfxVi/cNO3HWnoDeNGpQ94H6E=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-j/qMS792IFr0Cn/cFUargHSOTw4vz79kr58XhJVikBQ=";
  };

  patches = [ ./nixflix-request-first.patch ];

  buildInputs = [ sqlite ];

  nativeBuildInputs = [
    makeWrapper
    node-gyp
    nodejs
    pkg-config
    pnpm
    pnpmConfigHook
    python3
    python3Packages.distutils
    xcbuild
  ];

  env = {
    npm_config_build_from_source = "true";
    npm_config_nodedir = "${nodejs}";
    npm_config_sqlite = sqlite.dev;
  };

  preBuild = builtins.readFile ./pre-build.sh;
  buildPhase = builtins.readFile ./build-phase.sh;
  installPhase = builtins.readFile ./install-phase.sh;
  postInstall = builtins.readFile (
    replaceVars ./post-install.sh {
      nodejs = "${nodejs}";
    }
  );

  meta = {
    description = "Request management and media discovery for Plex";
    homepage = "https://github.com/seerr-team/seerr";
    license = lib.licenses.mit;
    mainProgram = "seerr";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
