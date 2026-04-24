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
      daemon = evaluated.config.launchd.daemons.prowlarr.serviceConfig;
    in
    assertTest "darwin-prowlarr-basic" (
      evaluated.config.launchd.daemons ? prowlarr
      && evaluated.config.launchd.daemons ? prowlarr-config
      && daemon ? ProgramArguments
      && builtins.length daemon.ProgramArguments == 1
      && builtins.isString (builtins.elemAt daemon.ProgramArguments 0)
      && builtins.isString (
        builtins.elemAt evaluated.config.launchd.daemons.prowlarr-config.serviceConfig.ProgramArguments 0
      )
      && daemon.UserName == "_nixflix"
      && daemon.GroupName == "_nixflix"
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
                rootFolders = [ { path = "/media/tv"; } ];
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
              };
            };
          };
        }
      ];
    in
    assertTest "darwin-arr-basic" (
      evaluated.config.launchd.daemons ? sonarr
      && evaluated.config.launchd.daemons ? sonarr-config
      && !(evaluated.config.launchd.daemons ? sonarr-rootfolders)
      && !(evaluated.config.launchd.daemons ? sonarr-delayprofiles)
      && builtins.isString (
        builtins.elemAt evaluated.config.launchd.daemons.sonarr.serviceConfig.ProgramArguments 0
      )
      && builtins.isString (
        builtins.elemAt evaluated.config.launchd.daemons.sonarr-config.serviceConfig.ProgramArguments 0
      )
      && evaluated.config.launchd.daemons ? sonarr-anime
      && evaluated.config.launchd.daemons ? sonarr-anime-config
      && !(evaluated.config.launchd.daemons ? sonarr-anime-rootfolders)
      && !(evaluated.config.launchd.daemons ? sonarr-anime-delayprofiles)
      && evaluated.config.launchd.daemons ? radarr
      && evaluated.config.launchd.daemons ? radarr-config
      && !(evaluated.config.launchd.daemons ? radarr-rootfolders)
      && !(evaluated.config.launchd.daemons ? radarr-delayprofiles)
      && evaluated.config.launchd.daemons.sonarr.serviceConfig.UserName == "_nixflix"
      && evaluated.config.launchd.daemons.radarr.serviceConfig.UserName == "_nixflix"
      && evaluated.config.nixflix.sonarr.config.hostConfig.bindAddress == "*"
      && evaluated.config.nixflix.radarr.config.hostConfig.bindAddress == "*"
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
      script = builtins.elemAt evaluated.config.launchd.daemons.prowlarr-config.serviceConfig.ProgramArguments 0;
    in
    pkgs.runCommand "darwin-test-darwin-prowlarr-applications" { } ''
      ${lib.optionalString (
        !(
          evaluated.config.launchd.daemons ? prowlarr-config
          && !(evaluated.config.launchd.daemons ? prowlarr-applications)
          && builtins.length evaluated.config.nixflix.prowlarr.config.applications == 2
        )
      ) "echo 'FAIL: darwin-prowlarr-applications' && exit 1"}
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "radarr-wait-for-api"} '${script}'
      ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "sonarr-wait-for-api"} '${script}'
      if ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg "7878/api/v3/system/status"} '${script}'; then
        echo 'FAIL: darwin-prowlarr-applications uses unauthenticated Radarr wait'
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
      script = builtins.elemAt evaluated.config.launchd.daemons.prowlarr-config.serviceConfig.ProgramArguments 0;
    in
    pkgs.runCommand "darwin-test-darwin-prowlarr-indexers" { } ''
      ${lib.optionalString (
        !(
          evaluated.config.launchd.daemons ? prowlarr-config
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
      daemon = evaluated.config.launchd.daemons.qbittorrent.serviceConfig;
      activation = evaluated.config.system.activationScripts.users.text;
    in
    assertTest "darwin-qbittorrent-basic" (
      evaluated.config.launchd.daemons ? qbittorrent
      && daemon ? ProgramArguments
      && builtins.any (arg: lib.hasPrefix "--profile=" arg) daemon.ProgramArguments
      && builtins.any (arg: arg == "--webui-port=8282") daemon.ProgramArguments
      && daemon.UserName == "_nixflix"
      && daemon.GroupName == "_nixflix"
      && evaluated.config.nixflix.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Address == "*"
      && lib.hasInfix "qBittorrent.ini" activation
      && lib.hasInfix "launchctl bootout system/org.nixflix.qbittorrent" activation
      && !(lib.hasInfix "qBittorrent.conf" activation)
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
    in
    assertTest "darwin-downloadarr-basic" (
      evaluated.config.launchd.daemons ? sonarr-config
      && evaluated.config.launchd.daemons ? radarr-config
      && evaluated.config.launchd.daemons ? prowlarr-config
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
          && daemon.UserName == "_nixflix"
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
    in
    assertTest "darwin-system-mvp" (
      evaluated.config.users.groups ? _nixflix
      && evaluated.config.users.users._nixflix.isHidden
      && evaluated.config.users.users._nixflix.gid == evaluated.config.users.groups._nixflix.gid
      && daemons.jellyfin.serviceConfig.UserName == "_nixflix"
      && daemons.sonarr.serviceConfig.UserName == "_nixflix"
      && daemons.radarr.serviceConfig.UserName == "_nixflix"
      && daemons.prowlarr.serviceConfig.UserName == "_nixflix"
      && daemons.qbittorrent.serviceConfig.UserName == "_nixflix"
      && evaluated.config.nixflix.prowlarr.config.hostConfig.bindAddress == "*"
      && evaluated.config.nixflix.sonarr.config.hostConfig.bindAddress == "*"
      && evaluated.config.nixflix.radarr.config.hostConfig.bindAddress == "*"
      && evaluated.config.nixflix.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Address == "*"
      && daemons ? jellyfin-config
      && daemons ? sonarr-config
      && daemons ? radarr-config
      && daemons ? prowlarr-config
      && builtins.length evaluated.config.nixflix.prowlarr.config.indexers == 2
    );
}
