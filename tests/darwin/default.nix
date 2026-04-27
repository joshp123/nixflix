{
  lib,
  darwinModules,
  nixDarwin ? null,
  pkgs ? import <nixpkgs> { inherit system; },
  system ? builtins.currentSystem,
}:
let
  baseDarwin = {
    options = {
      assertions = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
      };
      system.activationScripts = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.text = lib.mkOption {
              type = lib.types.lines;
              default = "";
            };
          }
        );
        default = { };
      };
      launchd.daemons = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.serviceConfig = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
          }
        );
        default = { };
      };
      users = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
      environment.systemPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
      };
      warnings = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };

  evalConfig =
    modules:
    lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        baseDarwin
        darwinModules
      ]
      ++ modules;
    };

  assertTest =
    name: cond:
    pkgs.runCommand "darwin-test-${name}" { } ''
      ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
      echo 'PASS: ${name}' > $out
    '';

  hasCommand = name: commands: builtins.elem name (map (command: command.name) commands);

  findCommand =
    name: commands: builtins.head (builtins.filter (command: command.name == name) commands);
in
{
  darwin-eval-basic =
    let
      evaluated = evalConfig [
        {
          nixflix.enable = false;
        }
      ];
    in
    assertTest "darwin-eval-basic" (evaluated ? options && evaluated.options ? nixflix);

  darwin-prowlarr-basic =
    let
      evaluated = evalConfig [
        {
          nixflix = {
            enable = true;
            prowlarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/prowlarr-api-key";
                hostConfig.password._secret = "/tmp/prowlarr-password";
              };
            };
            nginx.enable = false;
          };
        }
      ];
      manifest = evaluated.config.nixflix.runtime.darwinSupervisorManifest;
      service = findCommand "prowlarr" manifest.services;
      job = findCommand "prowlarr-config" manifest.jobs;
    in
    assertTest "darwin-prowlarr-basic" (
      hasCommand "prowlarr" manifest.services
      && hasCommand "prowlarr-config" manifest.jobs
      && !(evaluated.config.launchd.daemons ? prowlarr)
      && builtins.length service.argv == 1
      && builtins.isString (builtins.elemAt service.argv 0)
      && builtins.isString (builtins.elemAt job.argv 0)
      && !(service ? UserName)
      && !(service ? GroupName)
    );

  darwin-arr-basic =
    let
      evaluated = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/sonarr-api-key";
                hostConfig.password._secret = "/tmp/sonarr-password";
                hostConfig.authenticationRequired = "disabledForLocalAddresses";
                rootFolders = [ { path = "/media/tv"; } ];
                qualityProfiles = [
                  {
                    name = "Best";
                    sourceName = "Ultra-HD";
                  }
                ];
                customFormats = [
                  {
                    name = "HDR";
                    specifications = [ ];
                    scores.Best = 500;
                  }
                ];
              };
            };
            sonarr-anime = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/sonarr-anime-api-key";
                hostConfig.password._secret = "/tmp/sonarr-anime-password";
                rootFolders = [ { path = "/media/anime"; } ];
              };
            };
            radarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/radarr-api-key";
                hostConfig.password._secret = "/tmp/radarr-password";
                rootFolders = [ { path = "/media/movies"; } ];
                qualityProfiles = [
                  {
                    name = "Best";
                    sourceName = "Ultra-HD";
                  }
                ];
                customFormats = [
                  {
                    name = "HDR";
                    specifications = [ ];
                    scores.Best = 500;
                  }
                ];
              };
            };
          };
        }
      ];
      manifest = evaluated.config.nixflix.runtime.darwinSupervisorManifest;
      sonarr = findCommand "sonarr" manifest.services;
      sonarrConfig = findCommand "sonarr-config" manifest.jobs;
      radarrConfig = findCommand "radarr-config" manifest.jobs;
    in
    pkgs.runCommand "darwin-test-darwin-arr-basic" { } ''
      ${lib.optionalString (
        !(
          hasCommand "sonarr" manifest.services
          && hasCommand "sonarr-config" manifest.jobs
          && !(evaluated.config.launchd.daemons ? sonarr)
          && !(evaluated.config.launchd.daemons ? sonarr-rootfolders)
          && !(evaluated.config.launchd.daemons ? sonarr-delayprofiles)
          && !(evaluated.config.launchd.daemons ? sonarr-qualityprofiles)
          && !(evaluated.config.launchd.daemons ? sonarr-customformats)
          && builtins.isString (builtins.elemAt sonarr.argv 0)
          && sonarr.env.SONARR__AUTH__REQUIRED == "DisabledForLocalAddresses"
          && builtins.isString (builtins.elemAt sonarrConfig.argv 0)
          && hasCommand "sonarr-anime" manifest.services
          && hasCommand "sonarr-anime-config" manifest.jobs
          && !(evaluated.config.launchd.daemons ? sonarr-anime)
          && !(evaluated.config.launchd.daemons ? sonarr-anime-rootfolders)
          && !(evaluated.config.launchd.daemons ? sonarr-anime-delayprofiles)
          && hasCommand "radarr" manifest.services
          && hasCommand "radarr-config" manifest.jobs
          && !(evaluated.config.launchd.daemons ? radarr)
          && !(evaluated.config.launchd.daemons ? radarr-rootfolders)
          && !(evaluated.config.launchd.daemons ? radarr-delayprofiles)
          && !(evaluated.config.launchd.daemons ? radarr-qualityprofiles)
          && !(evaluated.config.launchd.daemons ? radarr-customformats)
          && builtins.isString (builtins.elemAt radarrConfig.argv 0)
          && evaluated.config.nixflix.sonarr.config.hostConfig.bindAddress == "*"
          && evaluated.config.nixflix.radarr.config.hostConfig.bindAddress == "*"
        )
      ) "echo 'FAIL: darwin-arr-basic' && exit 1"}
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "configure-quality-profiles.sh"} '${builtins.elemAt sonarrConfig.argv 0}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "configure-quality-profiles.sh"} '${builtins.elemAt radarrConfig.argv 0}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "configure-custom-formats.sh"} '${builtins.elemAt sonarrConfig.argv 0}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "configure-custom-formats.sh"} '${builtins.elemAt radarrConfig.argv 0}'
      echo 'PASS: darwin-arr-basic' > $out
    '';

  darwin-bazarr-basic =
    let
      evaluated = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/sonarr-api-key";
                hostConfig.password._secret = "/tmp/sonarr-password";
              };
            };
            radarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/radarr-api-key";
                hostConfig.password._secret = "/tmp/radarr-password";
              };
            };
            bazarr = {
              enable = true;
              config.opensubtitlescom = {
                username._secret = "/tmp/opensubtitles-username";
                password._secret = "/tmp/opensubtitles-password";
              };
            };
          };
        }
      ];
      manifest = evaluated.config.nixflix.runtime.darwinSupervisorManifest;
      service = findCommand "bazarr" manifest.services;
      activation = evaluated.config.system.activationScripts.postActivation.text;
    in
    pkgs.runCommand "darwin-test-darwin-bazarr-basic" { } ''
      ${lib.optionalString (
        !(
          hasCommand "bazarr" manifest.services
          && builtins.length service.argv == 6
          && builtins.elem "--no-update" service.argv
          && !(evaluated.config.launchd.daemons ? bazarr)
          && evaluated.config.nixflix.bazarr.user == "nixflix"
          && evaluated.config.nixflix.bazarr.group == "staff"
        )
      ) "echo 'FAIL: darwin-bazarr-basic' && exit 1"}
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "write-bazarr-config.sh"} <<< ${lib.escapeShellArg activation}
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "/bazarr"} <<< ${lib.escapeShellArg activation}
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "/tmp/opensubtitles-username"} <<< ${lib.escapeShellArg activation}
      echo 'PASS: darwin-bazarr-basic' > $out
    '';

  darwin-seerr-basic =
    let
      evaluated = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;
              seerr = {
                enable = true;
                settings = {
                  discover.enableBuiltInSliders = false;
                  users.defaultPermissions = 7168;
                };
                plex = {
                enable = true;
                hostname = "192.168.1.163";
              };
              radarr.Radarr = {
                apiKey._secret = "/tmp/radarr-api-key";
                baseUrl = "/radarr";
                activeProfileName = "Best";
                activeDirectory = "/media/movies";
                preventSearch = true;
              };
              sonarr.Sonarr = {
                apiKey._secret = "/tmp/sonarr-api-key";
                baseUrl = "/sonarr";
                activeProfileName = "Best";
                activeAnimeProfileName = "Best";
                activeDirectory = "/media/tv";
                preventSearch = true;
              };
            };
            radarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/radarr-api-key";
                hostConfig.password._secret = "/tmp/radarr-password";
              };
            };
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/sonarr-api-key";
                hostConfig.password._secret = "/tmp/sonarr-password";
              };
            };
          };
        }
      ];
      manifest = evaluated.config.nixflix.runtime.darwinSupervisorManifest;
      service = findCommand "seerr" manifest.services;
      job = findCommand "seerr-plex-config" manifest.jobs;
      radarrJob = findCommand "seerr-radarr-config-Radarr" manifest.jobs;
      sonarrJob = findCommand "seerr-sonarr-config-Sonarr" manifest.jobs;
      usersJob = findCommand "seerr-users-config" manifest.jobs;
      discoverJob = findCommand "seerr-discover-config" manifest.jobs;
      radarrPruneJob = findCommand "seerr-radarr-prune" manifest.jobs;
      sonarrPruneJob = findCommand "seerr-sonarr-prune" manifest.jobs;
      activation = evaluated.config.system.activationScripts.postActivation.text;
    in
    assertTest "darwin-seerr-basic" (
      hasCommand "seerr" manifest.services
      && hasCommand "seerr-plex-config" manifest.jobs
      && hasCommand "seerr-radarr-config-Radarr" manifest.jobs
      && hasCommand "seerr-sonarr-config-Sonarr" manifest.jobs
      && hasCommand "seerr-users-config" manifest.jobs
      && hasCommand "seerr-discover-config" manifest.jobs
      && hasCommand "seerr-radarr-prune" manifest.jobs
      && hasCommand "seerr-sonarr-prune" manifest.jobs
      && builtins.length service.argv == 1
      && builtins.elem "192.168.1.163" job.argv
      && builtins.elem "/tmp/radarr-api-key" radarrJob.argv
      && builtins.elem "/tmp/sonarr-api-key" sonarrJob.argv
      && builtins.any (
        arg: lib.hasInfix "seerr-radarr-configured-names.json" (toString arg)
      ) radarrPruneJob.argv
      && builtins.any (
        arg: lib.hasInfix "seerr-sonarr-configured-names.json" (toString arg)
      ) sonarrPruneJob.argv
      && builtins.any (
        arg: lib.hasInfix "seerr-user-settings.json" (toString arg)
      ) usersJob.argv
      && builtins.elem "false" discoverJob.argv
      && service.cwd == toString evaluated.config.nixflix.seerr.dataDir
      && service.env.CONFIG_DIRECTORY == toString evaluated.config.nixflix.seerr.dataDir
      && service.env.HOST == "127.0.0.1"
      && service.env.PORT == "5055"
      && !(evaluated.config.launchd.daemons ? seerr)
      && evaluated.config.nixflix.seerr.user == "nixflix"
      && evaluated.config.nixflix.seerr.group == "staff"
      && lib.hasInfix "activate-seerr.sh" activation
    );

  darwin-prowlarr-applications =
    let
      evaluated = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;
            prowlarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/prowlarr-api-key";
                hostConfig.password._secret = "/tmp/prowlarr-password";
              };
            };
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/sonarr-api-key";
                hostConfig.password._secret = "/tmp/sonarr-password";
              };
            };
            radarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/radarr-api-key";
                hostConfig.password._secret = "/tmp/radarr-password";
              };
            };
          };
        }
      ];
      manifest = evaluated.config.nixflix.runtime.darwinSupervisorManifest;
      script = builtins.elemAt (findCommand "prowlarr-config" manifest.jobs).argv 0;
    in
    pkgs.runCommand "darwin-test-darwin-prowlarr-applications" { } ''
      ${lib.optionalString (
        !(
          hasCommand "prowlarr-config" manifest.jobs
          && !(evaluated.config.launchd.daemons ? prowlarr-applications)
          && builtins.length evaluated.config.nixflix.prowlarr.config.applications == 2
        )
      ) "echo 'FAIL: darwin-prowlarr-applications' && exit 1"}
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "radarr-wait-for-api"} '${script}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "sonarr-wait-for-api"} '${script}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "write-arr-config.sh"} '${builtins.elemAt (findCommand "prowlarr" manifest.services).argv 0}'
      if ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "7878/api/v3/system/status"} '${script}'; then
        echo 'FAIL: darwin-prowlarr-applications uses unauthenticated Radarr wait'
        exit 1
      fi
      if ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "Fetching indexer schemas"} '${script}'; then
        echo 'FAIL: darwin-prowlarr-applications deletes manual indexers when none are declared'
        exit 1
      fi
      echo 'PASS: darwin-prowlarr-applications' > $out
    '';

  darwin-prowlarr-indexers =
    let
      evaluated = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;
            prowlarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/prowlarr-api-key";
                hostConfig.password._secret = "/tmp/prowlarr-password";
                indexers = [
                  {
                    name = "PassThePopcorn";
                    username._secret = "/tmp/ptp-api-user";
                    apiKey._secret = "/tmp/ptp-api-key";
                    tags = [ "movies" ];
                  }
                  {
                    name = "BroadcasTheNet";
                    apiKey._secret = "/tmp/btn-api-key";
                    tags = [ "tv" ];
                  }
                ];
              };
            };
          };
        }
      ];
      manifest = evaluated.config.nixflix.runtime.darwinSupervisorManifest;
      script = builtins.elemAt (findCommand "prowlarr-config" manifest.jobs).argv 0;
    in
    pkgs.runCommand "darwin-test-darwin-prowlarr-indexers" { } ''
      ${lib.optionalString (
        !(
          hasCommand "prowlarr-config" manifest.jobs
          && !(evaluated.config.launchd.daemons ? prowlarr-indexers)
          && builtins.length evaluated.config.nixflix.prowlarr.config.indexers == 2
        )
      ) "echo 'FAIL: darwin-prowlarr-indexers' && exit 1"}
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "aPIKey"} '${script}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "aPIUser"} '${script}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "BroadcasTheNet"} '${script}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "Validating configured indexer secrets"} '${script}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "Private tracker APIs can ban invalid credentials"} '${script}'
      guard_line=$(${pkgs.gnugrep}/bin/grep -n ${lib.escapeShellArg "Validating configured indexer secrets"} '${script}' | ${pkgs.coreutils}/bin/cut -d: -f1)
      schema_line=$(${pkgs.gnugrep}/bin/grep -n ${lib.escapeShellArg "Fetching indexer schemas"} '${script}' | ${pkgs.coreutils}/bin/cut -d: -f1)
      if [ "$guard_line" -ge "$schema_line" ]; then
        echo 'FAIL: darwin-prowlarr-indexers validates fake secrets too late'
        exit 1
      fi
      echo 'PASS: darwin-prowlarr-indexers' > $out
    '';

  darwin-qbittorrent-basic =
    let
      evaluated = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;
            torrentClients.qbittorrent = {
              enable = true;
              webuiPort = 8282;
              password = "test123";
              categories = {
                movies = "/downloads/torrent/movies";
                tv = "/downloads/torrent/tv";
              };
              serverConfig = {
                LegalNotice.Accepted = true;
                Preferences.WebUI.Username = "admin";
                Preferences.WebUI.Password_PBKDF2 = "@ByteArray(mLsFJ3Dsd3+uZt52Vu9FxA==:ON7uV17wWL0mlay5m5i7PYeBusWa7dgiH+eJG8wC/t+zihfqauUTS0q6DKTwsB5YtbOcmztixnuezjjApywXlw==)";
              };
            };
          };
        }
      ];
      manifest = evaluated.config.nixflix.runtime.darwinSupervisorManifest;
      service = findCommand "qbittorrent" manifest.services;
      activation = evaluated.config.system.activationScripts.users.text;
      postActivation = evaluated.config.system.activationScripts.postActivation.text;
    in
    assertTest "darwin-qbittorrent-basic" (
      hasCommand "qbittorrent" manifest.services
      && !(evaluated.config.launchd.daemons ? qbittorrent)
      && builtins.any (arg: lib.hasPrefix "--profile=" arg) service.argv
      && builtins.any (arg: arg == "--webui-port=8282") service.argv
      && evaluated.config.nixflix.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Address == "*"
      && lib.hasInfix "qBittorrent.ini" activation
      && !(lib.hasInfix "qBittorrent.conf" activation)
      && lib.hasInfix "install-supervisor.sh" postActivation
      && !(lib.hasInfix "supervisor-launchagent.plist" postActivation)
    );

  darwin-downloadarr-basic =
    let
      evaluated = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;
            downloadarr.enable = true;
            torrentClients.qbittorrent = {
              enable = true;
              webuiPort = 8282;
              password = "test123";
              serverConfig = {
                LegalNotice.Accepted = true;
                Preferences.WebUI.Username = "admin";
                Preferences.WebUI.Password_PBKDF2 = "@ByteArray(mLsFJ3Dsd3+uZt52Vu9FxA==:ON7uV17wWL0mlay5m5i7PYeBusWa7dgiH+eJG8wC/t+zihfqauUTS0q6DKTwsB5YtbOcmztixnuezjjApywXlw==)";
              };
            };
            prowlarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/prowlarr-api-key";
                hostConfig.password._secret = "/tmp/prowlarr-password";
              };
            };
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/sonarr-api-key";
                hostConfig.password._secret = "/tmp/sonarr-password";
                rootFolders = [ { path = "/media/tv"; } ];
              };
            };
            radarr = {
              enable = true;
              config = {
                apiKey._secret = "/tmp/radarr-api-key";
                hostConfig.password._secret = "/tmp/radarr-password";
                rootFolders = [ { path = "/media/movies"; } ];
              };
            };
          };
        }
      ];
      manifest = evaluated.config.nixflix.runtime.darwinSupervisorManifest;
    in
    assertTest "darwin-downloadarr-basic" (
      hasCommand "sonarr-config" manifest.jobs
      && hasCommand "radarr-config" manifest.jobs
      && hasCommand "prowlarr-config" manifest.jobs
      && !(evaluated.config.launchd.daemons ? sonarr-downloadclients)
      && !(evaluated.config.launchd.daemons ? radarr-downloadclients)
      && !(evaluated.config.launchd.daemons ? prowlarr-downloadclients)
    );

  darwin-eval-jellyfin =
    let
      evaluated = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;
            jellyfin = {
              enable = true;
              apiKey._secret = "/tmp/jellyfin-api-key";
              users.admin = {
                password._secret = "/tmp/jellyfin-admin-password";
                policy.isAdministrator = true;
              };
            };
            sonarr = {
              enable = true;
              mediaDirs = [ "/media/tv" ];
              config = {
                apiKey._secret = "/tmp/sonarr-api-key";
                hostConfig.password._secret = "/tmp/sonarr-password";
              };
            };
            radarr = {
              enable = true;
              mediaDirs = [ "/media/movies" ];
              config = {
                apiKey._secret = "/tmp/radarr-api-key";
                hostConfig.password._secret = "/tmp/radarr-password";
              };
            };
          };
        }
      ];
      daemon = evaluated.config.launchd.daemons.jellyfin.serviceConfig;
      configScript = builtins.elemAt evaluated.config.launchd.daemons.jellyfin-config.serviceConfig.ProgramArguments 0;
      inherit (evaluated.config.nixflix.jellyfin) libraries;
    in
    pkgs.runCommand "darwin-test-darwin-eval-jellyfin" { } ''
      ${lib.optionalString (
        !(
          evaluated.config.launchd.daemons ? jellyfin
          && evaluated.config.launchd.daemons ? jellyfin-config
          && daemon ? ProgramArguments
          && builtins.elem "--datadir" daemon.ProgramArguments
          && daemon.UserName == "nixflix"
          && libraries ? Shows
          && libraries ? Movies
          && libraries.Shows.paths == [ "/media/tv" ]
          && libraries.Movies.paths == [ "/media/movies" ]
        )
      ) "echo 'FAIL: darwin-eval-jellyfin' && exit 1"}
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "("} '${configScript}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "API key is already correct"} '${configScript}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "Configuring Jellyfin system settings"} '${configScript}'
      echo 'PASS: darwin-eval-jellyfin' > $out
    '';
}
// lib.optionalAttrs (nixDarwin != null) {
  darwin-system-mvp =
    let
      evaluated = nixDarwin.darwinSystem {
        inherit system;
        modules = [
          darwinModules
          {
            nixpkgs.hostPlatform = system;
            system.stateVersion = 6;
            nixflix = {
              enable = true;
              nginx.enable = false;
              jellyfin = {
                enable = true;
                apiKey._secret = "/tmp/jellyfin-api-key";
                users.admin.password._secret = "/tmp/jellyfin-admin-password";
              };
              torrentClients.qbittorrent = {
                enable = true;
                password = "test-password";
                serverConfig = {
                  LegalNotice.Accepted = true;
                  Preferences.WebUI.Username = "admin";
                  Preferences.WebUI.Password_PBKDF2 = "@ByteArray(mLsFJ3Dsd3+uZt52Vu9FxA==:ON7uV17wWL0mlay5m5i7PYeBusWa7dgiH+eJG8wC/t+zihfqauUTS0q6DKTwsB5YtbOcmztixnuezjjApywXlw==)";
                };
              };
              downloadarr.enable = true;
              prowlarr = {
                enable = true;
                config = {
                  apiKey._secret = "/tmp/prowlarr-api-key";
                  hostConfig.password._secret = "/tmp/prowlarr-password";
                  indexers = [
                    {
                      name = "PassThePopcorn";
                      username._secret = "/tmp/ptp-api-user";
                      apiKey._secret = "/tmp/ptp-api-key";
                      tags = [ "movies" ];
                    }
                    {
                      name = "BroadcasTheNet";
                      apiKey._secret = "/tmp/btn-api-key";
                      tags = [ "tv" ];
                    }
                  ];
                };
              };
              sonarr = {
                enable = true;
                config = {
                  apiKey._secret = "/tmp/sonarr-api-key";
                  hostConfig.password._secret = "/tmp/sonarr-password";
                };
              };
              radarr = {
                enable = true;
                config = {
                  apiKey._secret = "/tmp/radarr-api-key";
                  hostConfig.password._secret = "/tmp/radarr-password";
                };
              };
            };
          }
        ];
      };
      inherit (evaluated.config.launchd) daemons;
      manifest = evaluated.config.nixflix.runtime.darwinSupervisorManifest;
    in
    assertTest "darwin-system-mvp" (
      evaluated.config.users.users.nixflix.isHidden
      && evaluated.config.users.users.nixflix.gid == 20
      && daemons.jellyfin.serviceConfig.UserName == "nixflix"
      && hasCommand "sonarr" manifest.services
      && hasCommand "radarr" manifest.services
      && hasCommand "prowlarr" manifest.services
      && hasCommand "qbittorrent" manifest.services
      && evaluated.config.nixflix.prowlarr.config.hostConfig.bindAddress == "*"
      && evaluated.config.nixflix.sonarr.config.hostConfig.bindAddress == "*"
      && evaluated.config.nixflix.radarr.config.hostConfig.bindAddress == "*"
      && evaluated.config.nixflix.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Address == "*"
      && daemons ? jellyfin-config
      && hasCommand "sonarr-config" manifest.jobs
      && hasCommand "radarr-config" manifest.jobs
      && hasCommand "prowlarr-config" manifest.jobs
      && builtins.length evaluated.config.nixflix.prowlarr.config.indexers == 2
    );
}
