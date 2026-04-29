{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.seerr;
  stateDir = toString cfg.dataDir;
  logDir = "${stateDir}/logs";
  activateSeerr = builtins.path {
    path = ./scripts/activate-seerr.sh;
    name = "activate-seerr.sh";
  };
  configurePlex = builtins.path {
    path = ./scripts/configure-seerr-plex.sh;
    name = "configure-seerr-plex.sh";
  };
  configureArr = builtins.path {
    path = ./scripts/configure-seerr-arr.sh;
    name = "configure-seerr-arr.sh";
  };
  configureDiscover = builtins.path {
    path = ./scripts/configure-seerr-discover.sh;
    name = "configure-seerr-discover.sh";
  };
  configureUsers = builtins.path {
    path = ./scripts/configure-seerr-users.sh;
    name = "configure-seerr-users.sh";
  };
  pruneArr = builtins.path {
    path = ./scripts/prune-seerr-arr.sh;
    name = "prune-seerr-arr.sh";
  };
  seerrPackage = pkgs.callPackage ../../../pkgs/seerr { };
  secrets = import ../../../lib/secrets { inherit lib; };
  libraryNamesFile = pkgs.writeText "seerr-plex-library-names.json" (
    builtins.toJSON cfg.plex.libraryNames
  );
  userSettingsFile = pkgs.writeText "seerr-user-settings.json" (builtins.toJSON cfg.settings.users);
  managedUsersFile = pkgs.writeText "seerr-managed-users.json" (builtins.toJSON cfg.managedUsers);
  discoverSliderTypeIds = {
    RECENTLY_ADDED = 1;
    RECENT_REQUESTS = 2;
    PLEX_WATCHLIST = 3;
    TRENDING = 4;
    POPULAR_MOVIES = 5;
    MOVIE_GENRES = 6;
    UPCOMING_MOVIES = 7;
    STUDIOS = 8;
    POPULAR_TV = 9;
    TV_GENRES = 10;
    UPCOMING_TV = 11;
    NETWORKS = 12;
  };
  discoverEnabledTypesFile = pkgs.writeText "seerr-discover-enabled-types.json" (
    builtins.toJSON (
      map (type: discoverSliderTypeIds.${type}) cfg.settings.discover.enabledBuiltInSliderTypes
    )
  );
  secretArgs =
    value:
    if secrets.isSecretRef value then
      [
        "file"
        (toString value._secret)
      ]
    else
      [
        "literal"
        (toString value)
      ];
  mkConfigFile =
    kind: name: values:
    pkgs.writeText "seerr-${kind}-${name}.json" (
      builtins.toJSON (
        {
          inherit name;
          inherit (values)
            hostname
            port
            useSsl
            baseUrl
            activeProfileName
            activeDirectory
            is4k
            isDefault
            externalUrl
            syncEnabled
            preventSearch
            ;
        }
        // optionalAttrs (kind == "radarr") {
          inherit (values) minimumAvailability;
        }
        // optionalAttrs (kind == "sonarr") {
          inherit (values)
            activeAnimeProfileName
            activeAnimeDirectory
            seriesType
            animeSeriesType
            enableSeasonFolders
            ;
        }
      )
    );
  mkArrJob =
    kind: name: values:
    let
      configFile = mkConfigFile kind name values;
    in
    {
      name = "seerr-${kind}-config-${builtins.replaceStrings [ " " "-" ] [ "_" "_" ] name}";
      argv = [
        "/bin/bash"
        configureArr
        "${pkgs.curl}/bin/curl"
        "${pkgs.jq}/bin/jq"
        "http://127.0.0.1:${toString cfg.port}"
        "${stateDir}/settings.json"
        kind
        configFile
      ]
      ++ secretArgs values.apiKey;
      cwd = stateDir;
      stdout = "${logDir}/seerr-${kind}-config-${name}.stdout.log";
      stderr = "${logDir}/seerr-${kind}-config-${name}.stderr.log";
      env = {
        HOME = stateDir;
        PATH = "${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.curl
            pkgs.jq
          ]
        }:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  arrJobs =
    (mapAttrsToList (mkArrJob "radarr") cfg.radarr) ++ (mapAttrsToList (mkArrJob "sonarr") cfg.sonarr);
  mkPruneJob =
    kind: names:
    let
      configuredNamesFile = pkgs.writeText "seerr-${kind}-configured-names.json" (builtins.toJSON names);
    in
    {
      name = "seerr-${kind}-prune";
      argv = [
        "/bin/bash"
        pruneArr
        "${pkgs.curl}/bin/curl"
        "${pkgs.jq}/bin/jq"
        "http://127.0.0.1:${toString cfg.port}"
        "${stateDir}/settings.json"
        kind
        configuredNamesFile
      ];
      cwd = stateDir;
      stdout = "${logDir}/seerr-${kind}-prune.stdout.log";
      stderr = "${logDir}/seerr-${kind}-prune.stderr.log";
      env = {
        HOME = stateDir;
        PATH = "${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.curl
            pkgs.jq
          ]
        }:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  pruneJobs =
    optional (cfg.radarr != { }) (mkPruneJob "radarr" (attrNames cfg.radarr))
    ++ optional (cfg.sonarr != { }) (mkPruneJob "sonarr" (attrNames cfg.sonarr));
  serviceSpec = {
    name = "seerr";
    argv = [ "${getExe cfg.package}" ];
    cwd = stateDir;
    stdout = "${logDir}/stdout.log";
    stderr = "${logDir}/stderr.log";
    env = {
      CONFIG_DIRECTORY = stateDir;
      HOST = "127.0.0.1";
      PORT = toString cfg.port;
    };
  };
  plexJob = {
    name = "seerr-plex-config";
    argv = [
      "/bin/bash"
      configurePlex
      "${pkgs.curl}/bin/curl"
      "${pkgs.jq}/bin/jq"
      "http://127.0.0.1:${toString cfg.port}"
      "${stateDir}/settings.json"
      cfg.plex.hostname
      (toString cfg.plex.port)
      (boolToString cfg.plex.useSsl)
      cfg.plex.webAppUrl
      (boolToString cfg.plex.enableAllLibraries)
      libraryNamesFile
    ];
    cwd = stateDir;
    stdout = "${logDir}/seerr-plex-config.stdout.log";
    stderr = "${logDir}/seerr-plex-config.stderr.log";
    env = {
      HOME = stateDir;
      PATH = "${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
        ]
      }:/usr/bin:/bin:/usr/sbin:/sbin";
    };
  };
  discoverJob = {
    name = "seerr-discover-config";
    argv = [
      "/bin/bash"
      configureDiscover
      "${pkgs.curl}/bin/curl"
      "${pkgs.jq}/bin/jq"
      "http://127.0.0.1:${toString cfg.port}"
      "${stateDir}/settings.json"
      discoverEnabledTypesFile
    ];
    cwd = stateDir;
    stdout = "${logDir}/seerr-discover-config.stdout.log";
    stderr = "${logDir}/seerr-discover-config.stderr.log";
    env = {
      HOME = stateDir;
      PATH = "${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
        ]
      }:/usr/bin:/bin:/usr/sbin:/sbin";
    };
  };
  usersJob = {
    name = "seerr-users-config";
    argv = [
      "/bin/bash"
      configureUsers
      "${pkgs.curl}/bin/curl"
      "${pkgs.jq}/bin/jq"
      "http://127.0.0.1:${toString cfg.port}"
      "${stateDir}/settings.json"
      userSettingsFile
      managedUsersFile
    ];
    cwd = stateDir;
    stdout = "${logDir}/seerr-users-config.stdout.log";
    stderr = "${logDir}/seerr-users-config.stderr.log";
    env = {
      HOME = stateDir;
      PATH = "${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
        ]
      }:/usr/bin:/bin:/usr/sbin:/sbin";
    };
  };
in
{
  imports = [ ../../seerr/options ];

  options.nixflix.seerr.managedUsers = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            email = mkOption {
              type = types.str;
              default = name;
              description = "Seerr user email address to manage.";
            };

            permissions = mkOption {
              type = types.int;
              description = "Exact Seerr permission bitmask to enforce for this user.";
            };
          };
        }
      )
    );
    default = { };
    description = "Existing Seerr users whose permissions should be reconciled by the Darwin backend.";
    example = {
      "user@example.com".permissions = 8224;
    };
  };

  config = mkIf (config.nixflix.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.user != "root" && cfg.group != "wheel";
        message = "nixflix.seerr must not run as root:wheel on Darwin.";
      }
    ];

    nixflix.seerr = {
      package = mkDefault seerrPackage;
      user = mkOverride 900 "nixflix";
      group = mkOverride 900 "staff";
    };

    system.activationScripts.postActivation.text = mkOrder 2000 "/bin/bash ${
      escapeShellArgs [
        activateSeerr
        stateDir
        logDir
        cfg.user
        cfg.group
      ]
    }\n";

    nixflix.runtime.darwinSupervisorManifest.services = [ serviceSpec ];
    nixflix.runtime.darwinSupervisorManifest.jobs =
      optional cfg.plex.enable plexJob
      ++ [ usersJob ]
      ++ optional (cfg.settings.discover.enabledBuiltInSliderTypes != null) discoverJob
      ++ arrJobs
      ++ pruneJobs;
  };
}
