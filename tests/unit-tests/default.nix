{
  system ? builtins.currentSystem,
  pkgs ? import <nixpkgs> { inherit system; },
  nixosModules,
}:
let
  inherit (pkgs) lib;
  jellyfinPlugins = import ../../lib/jellyfin-plugins.nix { inherit lib; };
  manifestHash =
    file:
    builtins.convertHash {
      hash = builtins.hashFile "sha256" file;
      hashAlgo = "sha256";
      toHashFormat = "sri";
    };

  # Helper to evaluate a NixOS configuration without building
  evalConfig =
    modules:
    import "${pkgs.path}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        nixosModules
        {
          # Minimal NixOS config stubs needed for evaluation
          nixpkgs.hostPlatform = system;
        }
      ]
      ++ modules;
    };

  # Test helper to assert conditions
  assertTest =
    name: cond:
    pkgs.runCommand "unit-test-${name}" { } ''
      ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
      echo 'PASS: ${name}' > $out
    '';

  check = name: cond: ''
    ${lib.optionalString (!cond) "echo 'FAIL: ${name}' && exit 1"}
    echo 'PASS: ${name}'
  '';

  forbiddenMediaMutationPatterns = [
    "indexer/test"
    "/api/v1/indexer"
    "/api/v1/search"
    "/api/v1/command"
    "/api/v3/command"
    "/api/v3/indexer"
    "/api/v3/downloadclient/test"
    "/api/v3/notification/test"
    "/api/v3/importlist/test"
    "/api/v3/indexer/test"
    "/api/v3/release"
    "grab"
    "release/push"
    "settings/jellyfin"
    "library?sync"
    "settings/plex/sync"
    "/api/v1/request"
    "DELETE"
    "-X DELETE"
    "--request DELETE"
    "deleteUnmanaged"
    "prune"
    "chown -R /Volumes"
    "chmod -R /Volumes"
    "/Volumes/NAS"
  ];

  hasNoForbiddenMediaMutations = script: lib.all (pattern: !lib.hasInfix pattern script) forbiddenMediaMutationPatterns;
in
{
  # Test that nixflix.sonarr options generate correct systemd units
  sonarr-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              user = "testuser";
              config = {
                hostConfig = {
                  port = 8989;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
                apiKey._secret = "/run/secrets/sonarr-api";
                rootFolders = [ { path = "/media/tv"; } ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? sonarr && systemdUnits ? sonarr-config && systemdUnits ? sonarr-rootfolders;
    in
    assertTest "sonarr-service-generation" hasAllServices;

  # Test that nixflix.sonarr-anime options generate correct systemd units
  sonarr-anime-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr-anime = {
              enable = true;
              user = "testuser";
              config = {
                hostConfig = {
                  port = 8990;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
                apiKey._secret = "/run/secrets/sonarr-api";
                rootFolders = [ { path = "/media/anime"; } ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? sonarr-anime
        && systemdUnits ? sonarr-anime-config
        && systemdUnits ? sonarr-anime-rootfolders;
    in
    assertTest "sonarr-anime-service-generation" hasAllServices;

  # Test that radarr options generate correct systemd units
  radarr-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            radarr = {
              enable = true;
              user = "testuser";
              config = {
                hostConfig = {
                  port = 7878;
                  username = "admin";
                  password._secret = "/run/secrets/radarr-pass";
                };
                apiKey._secret = "/run/secrets/radarr-api";
                rootFolders = [ { path = "/media/movies"; } ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? radarr && systemdUnits ? radarr-config && systemdUnits ? radarr-rootfolders;
    in
    assertTest "radarr-service-generation" hasAllServices;

  # Test that prowlarr with indexers generates correct systemd units
  prowlarr-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            prowlarr = {
              enable = true;
              config = {
                hostConfig = {
                  port = 9696;
                  username = "admin";
                  password._secret = "/run/secrets/prowlarr-pass";
                };
                apiKey._secret = "/run/secrets/prowlarr-api";
                indexers = [
                  {
                    name = "1337x";
                    apiKey._secret = "/run/secrets/1337x-api";
                  }
                ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices =
        systemdUnits ? prowlarr && systemdUnits ? prowlarr-config && systemdUnits ? prowlarr-indexers;
    in
    assertTest "prowlarr-service-generation" hasAllServices;

  # Test that prowlarr with indexers generates correct systemd units
  sabnzbd-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            usenetClients.sabnzbd = {
              enable = true;
              downloadsDir = "/downloads/usenet";
              settings = {
                misc = {
                  api_key._secret = pkgs.writeText "sabnzbd-apikey" "testapikey123456789abcdef";
                  nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey123456789abcdef";
                  port = 8080;
                  host = "127.0.0.1";
                  url_base = "/sabnzbd";
                  ignore_samples = true;
                  direct_unpack = false;
                  article_tries = 5;
                };
                servers = [
                  {
                    name = "TestServer";
                    host = "news.example.com";
                    port = 563;
                    username._secret = pkgs.writeText "eweka-username" "testuser";
                    password._secret = pkgs.writeText "eweka-password" "testpass123";
                    connections = 10;
                    ssl = true;
                    priority = 0;
                  }
                ];
                categories = [
                  {
                    name = "tv";
                    dir = "tv";
                    priority = 0;
                    pp = 3;
                    script = "None";
                  }
                  {
                    name = "movies";
                    dir = "movies";
                    priority = 1;
                    pp = 2;
                    script = "None";
                  }
                ];
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      hasAllServices = systemdUnits ? sabnzbd;
    in
    assertTest "sabnzbd-service-generation" hasAllServices;

  # Test that seerr generates services with a remote Jellyfin (no local jellyfin)
  seerr-remote-jellyfin =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            seerr = {
              enable = true;
              apiKey._secret = "/run/secrets/seerr-api";
              jellyfin = {
                adminUsername = "remoteadmin";
                adminPassword = "remotepassword";
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
    in
    assertTest "seerr-remote-jellyfin" (
      systemdUnits ? seerr
      && systemdUnits ? seerr-setup
      && systemdUnits ? seerr-jellyfin
      && systemdUnits ? seerr-libraries
      && systemdUnits ? seerr-user-settings
    );

  seerr-request-first-policy-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            radarr = {
              enable = true;
              mediaDirs = [ "/media/movies" ];
              config = {
                apiKey._secret = "/run/secrets/radarr-api";
                hostConfig.urlBase = "/radarr";
              };
            };

            sonarr = {
              enable = true;
              mediaDirs = [ "/media/tv" ];
              config = {
                apiKey._secret = "/run/secrets/sonarr-api";
                hostConfig.urlBase = "/sonarr";
              };
            };

            seerr = {
              enable = true;
              manage.enable = false;
              requestFirst = {
                enable = true;
                plex.hostname = "192.168.1.163";
                managedUsers."katrossen@gmail.com" = { };
              };
            };
          };
        }
      ];
      cfg = config.config.nixflix.seerr.requestFirst;
      systemdUnits = config.config.systemd.services;
      unit = systemdUnits.${"seerr-request-first-policy"};
      script = unit.script;
      env = unit.environment;
      loadCredentials = unit.serviceConfig.LoadCredential or [ ];
      userSettings = builtins.fromJSON (builtins.readFile env.SEERR_USER_SETTINGS_JSON);
      managedUsers = builtins.fromJSON (builtins.readFile env.SEERR_MANAGED_USERS_JSON);
      discoverTypes = builtins.fromJSON (builtins.readFile env.SEERR_DISCOVER_ENABLED_TYPES_JSON);
      knownDiscoverTypes = builtins.fromJSON (builtins.readFile env.SEERR_DISCOVER_KNOWN_TYPES_JSON);
      radarrTargets = builtins.fromJSON (builtins.readFile env.SEERR_RADARR_TARGETS_JSON);
      sonarrTargets = builtins.fromJSON (builtins.readFile env.SEERR_SONARR_TARGETS_JSON);
      unitDisabledOrAbsent =
        name: (!builtins.hasAttr name systemdUnits) || !(systemdUnits.${name}.enable or false);
      broadSeerrUnits = [
        "seerr-setup"
        "seerr-radarr"
        "seerr-sonarr"
        "seerr-jellyfin"
        "seerr-libraries"
        "seerr-user-settings"
      ];
      forbidden = [
        "/api/v1/settings/radarr/test"
        "/api/v1/settings/sonarr/test"
        "/api/v1/request"
        "/api/v1/search"
        "/api/v1/command"
        "/api/v3/command"
        "/api/v3/indexer"
        "/api/v3/downloadclient/test"
        "/api/v3/notification/test"
        "/api/v3/importlist/test"
        "/api/v3/indexer/test"
        "/api/v3/release"
        "grab"
        "release/push"
        "settings/jellyfin"
        "library?sync"
        "settings/plex/sync"
        "settings/initialize"
        "DELETE"
        "chown -R /Volumes"
        "chmod -R /Volumes"
      ];
    in
    pkgs.runCommand "unit-test-seerr-request-first-policy-generation" { } ''
      ${check "request-first policy service exists" (
        builtins.hasAttr "seerr-request-first-policy" systemdUnits
      )}
      ${check "broad Seerr manage path remains disabled" (lib.all unitDisabledOrAbsent broadSeerrUnits)}
      ${check "request-first interface hides policy internals from host config" (
        !(builtins.hasAttr "defaultPermissions" cfg)
        && !(builtins.hasAttr "discover" cfg)
        && !(builtins.hasAttr "name" cfg.radarr)
        && !(builtins.hasAttr "activeProfileName" cfg.radarr)
        && !(builtins.hasAttr "preventSearch" cfg.radarr)
        && !(builtins.hasAttr "name" cfg.sonarr)
        && !(builtins.hasAttr "activeProfileName" cfg.sonarr)
        && !(builtins.hasAttr "activeAnimeProfileName" cfg.sonarr)
        && !(builtins.hasAttr "preventSearch" cfg.sonarr)
      )}
      ${check "request-first policy reads restored Seerr auth instead of restaging apiKey" (
        env.SEERR_SETTINGS_JSON == "/var/lib/seerr/settings.json"
        && env.SEERR_DB == "/var/lib/seerr/db/db.sqlite3"
        && lib.hasInfix ".main.apiKey" script
        && !(builtins.hasAttr "API_KEY" env)
      )}
      ${check "request-first policy allows empty Plex webAppUrl" (
        env.SEERR_PLEX_WEB_APP_URL == ""
        && lib.hasInfix "\${SEERR_PLEX_WEB_APP_URL:=}" script
        && !lib.hasInfix "\${SEERR_PLEX_WEB_APP_URL:?}" script
      )}
      ${check "request-first user and discover policy is generated" (
        userSettings.defaultPermissions == 8352
        && managedUsers.${"katrossen@gmail.com"}.email == "katrossen@gmail.com"
        && managedUsers.${"katrossen@gmail.com"}.permissions == 8352
        && discoverTypes == [ 1 ]
        &&
          lib.sort (left: right: left < right) knownDiscoverTypes == [
            1
            2
            3
            4
            5
            6
            7
            8
            9
            10
            11
            12
          ]
      )}
      ${check "request-first Arr credentials are systemd credentials" (
        lib.elem "radarr-Radarr_Best-apikey:/run/secrets/radarr-api" loadCredentials
        && lib.elem "sonarr-Sonarr_Best-apikey:/run/secrets/sonarr-api" loadCredentials
      )}
      ${check "policy script uses read-only Arr profile lookup" (
        lib.hasInfix "/api/v3/qualityprofile" script
      )}
      ${check "policy script merges restored Seerr settings without merging read-only Arr targets into PUT bodies" (
        lib.hasInfix "/api/v1/settings/main" script
        && lib.hasInfix "/api/v1/settings/plex" script
        && lib.hasInfix "$current + $policy" script
        && lib.hasInfix "existing_arr_target_for_compare" script
        && lib.hasInfix "del(.id)" script
        && !lib.hasInfix "$existing + $desired" script
        && lib.hasInfix "Seerr admin Plex token was lost" script
      )}
      ${check "policy script rejects stale-name local-endpoint duplicates" (
        lib.hasInfix "matched_id=" script
        && lib.hasInfix "localHost(.hostname)" script
        && lib.hasInfix "(.id | tostring) != $matchedId" script
        && lib.hasInfix "refusing to create duplicate Seerr $kind target" script
      )}
      ${check "policy script omits forbidden mutation paths" (
        lib.all (pattern: !lib.hasInfix pattern script) forbidden
      )}

      echo 'PASS: seerr-request-first-policy-generation' > $out
    '';

  seerr-request-first-api-key-assertion =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                seerr = {
                  enable = true;
                  apiKey._secret = "/run/secrets/seerr-api";
                  manage.enable = false;
                  requestFirst = {
                    enable = true;
                    radarr.enable = false;
                    sonarr.enable = false;
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "seerr-request-first-api-key-assertion" (!result.success);

  seerr-request-first-package-patch =
    let
      patchText = builtins.readFile ../../pkgs/seerr/nixflix-request-first.patch;
      package = pkgs.callPackage ../../pkgs/seerr { };
      patches = package.patches or [ ];
    in
    pkgs.runCommand "unit-test-seerr-request-first-package-patch"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.patch
        ];
      }
      ''
        ${check "Seerr package includes request-first nav patch" (
          patches == [ ../../pkgs/seerr/nixflix-request-first.patch ]
        )}
        ${check "request-first nav patch does not touch RequestButton" (
          !lib.hasInfix "RequestButton" patchText
        )}

        cp -R ${package.src} source
        chmod -R u+w source
        cd source
        patch -p1 < ${../../pkgs/seerr/nixflix-request-first.patch}

        mobile=src/components/Layout/MobileMenu/index.tsx
        sidebar=src/components/Layout/Sidebar/index.tsx
        for needle in \
          "href: '/discover/movies'" \
          "href: '/discover/tv'" \
          "content: intl.formatMessage(menuMessages.browsemovies)" \
          "content: intl.formatMessage(menuMessages.browsetv)" \
          "messagesKey: 'browsemovies'" \
          "messagesKey: 'browsetv'"; do
          if grep -F "$needle" "$mobile" "$sidebar" >/dev/null; then
            echo "FAIL: patched Seerr nav still contains $needle" >&2
            exit 1
          fi
        done

        echo 'PASS: seerr-request-first-package-patch' > $out
      '';

  bazarr-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            stateDir = "/var/lib/media";

            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/run/secrets/sonarr-api";
                hostConfig = {
                  bindAddress = "127.0.0.1";
                  port = 8989;
                  urlBase = "/sonarr";
                };
              };
            };

            radarr = {
              enable = true;
              config = {
                apiKey._secret = "/run/secrets/radarr-api";
                hostConfig = {
                  bindAddress = "127.0.0.1";
                  port = 7878;
                  urlBase = "/radarr";
                };
              };
            };

            bazarr = {
              enable = true;
              dataDir = "/var/lib/media/bazarr";
              openSubtitlesCom = {
                username._secret = "/run/secrets/opensubtitlescom-username";
                password._secret = "/run/secrets/opensubtitlescom-password";
              };
            };
          };
        }
      ];
      cfg = config.config.nixflix.bazarr;
      bazarrService = config.config.services.bazarr;
      unit = config.config.systemd.services.bazarr;
      execStartPreCommand = unit.serviceConfig.ExecStartPre;
      execStartPreScript = builtins.readFile (lib.removePrefix "+" execStartPreCommand);
      loadCredentials = unit.serviceConfig.LoadCredential or [ ];
      env = unit.environment;
      policyText = builtins.readFile env.BAZARR_POLICY_JSON;
      policy = builtins.fromJSON policyText;
    in
    pkgs.runCommand "unit-test-bazarr-service-generation" { } ''
      ${check "Bazarr service is owned by Nixflix" (
        bazarrService.enable
        && bazarrService.dataDir == "/var/lib/media/bazarr"
        && bazarrService.listenPort == 6767
        && bazarrService.user == "bazarr"
        && bazarrService.group == "media"
      )}
      ${check "Bazarr interface hides YAML policy knobs" (
        !(builtins.hasAttr "config" cfg)
        && !(builtins.hasAttr "general" cfg)
        && !(builtins.hasAttr "auth" cfg)
        && !(builtins.hasAttr "enabled_providers" cfg)
        && !(builtins.hasAttr "wanted_search_frequency" cfg)
        && !(builtins.hasAttr "opensubtitlescom" cfg)
        && !(builtins.hasAttr "enable" cfg.openSubtitlesCom)
        && !(builtins.hasAttr "required" cfg.openSubtitlesCom)
        && builtins.hasAttr "username" cfg.openSubtitlesCom
        && builtins.hasAttr "password" cfg.openSubtitlesCom
      )}
      ${check "Bazarr policy contains expected owned values" (
        policy.ownedValues.general.base_url == "/bazarr"
        && policy.ownedValues.general.ip == "127.0.0.1"
        && policy.ownedValues.general.port == 6767
        && policy.ownedValues.general.use_sonarr
        && policy.ownedValues.general.use_radarr
        && policy.ownedValues.general.minimum_score == 90
        && policy.ownedValues.general.minimum_score_movie == 80
        && policy.ownedValues.general.wanted_search_frequency == 876000
        && policy.ownedValues.general.wanted_search_frequency_movie == 876000
        && policy.ownedValues.auth.type == null
        && policy.ownedValues.sonarr.ip == "127.0.0.1"
        && policy.ownedValues.sonarr.port == 8989
        && policy.ownedValues.sonarr.base_url == "/sonarr"
        && policy.ownedValues.sonarr.series_sync == 10080
        && !policy.ownedValues.sonarr.series_sync_on_live
        && policy.ownedValues.radarr.ip == "127.0.0.1"
        && policy.ownedValues.radarr.port == 7878
        && policy.ownedValues.radarr.base_url == "/radarr"
        && policy.ownedValues.radarr.movies_sync == 10080
        && !policy.ownedValues.radarr.movies_sync_on_live
        && !policy.ownedValues.subsync.use_subsync
        && policy.requiredProviders == [ "opensubtitlescom" ]
        && policy.ownedValues.opensubtitlescom.use_hash
        && !policy.ownedValues.opensubtitlescom.include_ai_translated
        && !policy.ownedValues.opensubtitlescom.include_machine_translated
      )}
      ${check "Bazarr policy does not store credentials" (
        !lib.hasInfix "opensubtitlescom-username" policyText
        && !lib.hasInfix "opensubtitlescom-password" policyText
        && !lib.hasInfix "sonarr-api" policyText
        && !lib.hasInfix "radarr-api" policyText
      )}
      ${check "Bazarr credentials are systemd credentials" (
        lib.elem "sonarr-api-key:/run/secrets/sonarr-api" loadCredentials
        && lib.elem "radarr-api-key:/run/secrets/radarr-api" loadCredentials
        && lib.elem "opensubtitlescom-username:/run/secrets/opensubtitlescom-username" loadCredentials
        && lib.elem "opensubtitlescom-password:/run/secrets/opensubtitlescom-password" loadCredentials
        && env.BAZARR_SONARR_API_KEY_FILE == "/run/credentials/bazarr.service/sonarr-api-key"
        && env.BAZARR_RADARR_API_KEY_FILE == "/run/credentials/bazarr.service/radarr-api-key"
        &&
          env.BAZARR_OPENSUBTITLES_USERNAME_FILE
          == "/run/credentials/bazarr.service/opensubtitlescom-username"
        &&
          env.BAZARR_OPENSUBTITLES_PASSWORD_FILE
          == "/run/credentials/bazarr.service/opensubtitlescom-password"
      )}
      ${check "Bazarr pre-start is narrow and non-recursive" (
        execStartPreCommand != ""
        && lib.hasPrefix "+" execStartPreCommand
        && lib.hasInfix "writeConfig.py" execStartPreScript
        && lib.hasInfix "chown bazarr:media" execStartPreScript
        && lib.hasInfix "chmod 0640" execStartPreScript
        && !lib.hasInfix "chown -R" execStartPreScript
        && !lib.hasInfix "chmod -R" execStartPreScript
        && !lib.hasInfix "sqlite" execStartPreScript
        && !lib.hasInfix "/api/" execStartPreScript
      )}

      echo 'PASS: bazarr-service-generation' > $out
    '';

  bazarr-config-writer-merge =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/run/secrets/sonarr-api";
                hostConfig.urlBase = "/sonarr";
              };
            };
            radarr = {
              enable = true;
              config = {
                apiKey._secret = "/run/secrets/radarr-api";
                hostConfig.urlBase = "/radarr";
              };
            };
            bazarr = {
              enable = true;
              openSubtitlesCom = {
                username._secret = "/run/secrets/opensubtitlescom-username";
                password._secret = "/run/secrets/opensubtitlescom-password";
              };
            };
          };
        }
      ];
      policyFile = config.config.systemd.services.bazarr.environment.BAZARR_POLICY_JSON;
      python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
    in
    pkgs.runCommand "unit-test-bazarr-config-writer-merge"
      {
        nativeBuildInputs = [ pkgs.coreutils ];
      }
      ''
        mkdir -p state/config state/db
        cat > state/config/config.yaml <<'YAML'
        general:
          enabled_providers:
            - embeddedsubtitles
          language_equals:
            - en
          serie_default_profile: English Full
          movie_default_profile: English Full
          page_size: 25
        auth:
          apikey: keep-auth-api-key
          username: keep-auth-user
          type: forms
        sonarr:
          apikey: old-sonarr-key
          excluded_tags:
            - keep-sonarr-tag
        radarr:
          apikey: old-radarr-key
          excluded_tags:
            - keep-radarr-tag
        opensubtitlescom:
          username: old-open-user
          password: old-open-pass
          include_ai_translated: true
        movie_scores:
          hash: 119
        series_scores:
          series: 180
        YAML
        printf 'English Full profile DB placeholder\n' > state/db/bazarr.db
        db_before="$(sha256sum state/db/bazarr.db | cut -d ' ' -f1)"

        printf 'sonarr-secret\n' > sonarr-api
        printf 'radarr-secret\n' > radarr-api
        printf 'os-user\n' > os-user
        printf 'os-pass\n' > os-pass

        export BAZARR_SONARR_API_KEY_FILE="$PWD/sonarr-api"
        export BAZARR_RADARR_API_KEY_FILE="$PWD/radarr-api"
        export BAZARR_OPENSUBTITLES_USERNAME_FILE="$PWD/os-user"
        export BAZARR_OPENSUBTITLES_PASSWORD_FILE="$PWD/os-pass"
        export BAZARR_REQUIRE_OPENSUBTITLES=1

        ${python}/bin/python ${../../modules/bazarr/writeConfig.py} --state-dir "$PWD/state" --policy ${policyFile}

        db_after="$(sha256sum state/db/bazarr.db | cut -d ' ' -f1)"
        test "$db_before" = "$db_after"

        ${python}/bin/python - <<'PY'
        from pathlib import Path
        import yaml

        cfg = yaml.safe_load(Path("state/config/config.yaml").read_text())
        assert cfg["general"]["base_url"] == "/bazarr"
        assert cfg["general"]["ip"] == "127.0.0.1"
        assert cfg["general"]["port"] == 6767
        assert cfg["general"]["use_sonarr"] is True
        assert cfg["general"]["use_radarr"] is True
        assert cfg["general"]["language_equals"] == ["en"]
        assert cfg["general"]["serie_default_profile"] == "English Full"
        assert cfg["general"]["movie_default_profile"] == "English Full"
        assert cfg["general"]["page_size"] == 25
        assert set(cfg["general"]["enabled_providers"]) == {"embeddedsubtitles", "opensubtitlescom"}
        assert cfg["auth"]["type"] is None
        assert cfg["auth"]["apikey"] == "keep-auth-api-key"
        assert cfg["auth"]["username"] == "keep-auth-user"
        assert cfg["sonarr"]["apikey"] == "sonarr-secret"
        assert cfg["sonarr"]["excluded_tags"] == ["keep-sonarr-tag"]
        assert cfg["radarr"]["apikey"] == "radarr-secret"
        assert cfg["radarr"]["excluded_tags"] == ["keep-radarr-tag"]
        assert cfg["opensubtitlescom"]["username"] == "os-user"
        assert cfg["opensubtitlescom"]["password"] == "os-pass"
        assert cfg["opensubtitlescom"]["include_ai_translated"] is False
        assert cfg["movie_scores"]["hash"] == 119
        assert cfg["series_scores"]["series"] == 180
        PY

        echo 'PASS: bazarr-config-writer-merge' > $out
      '';

  bazarr-no-opensubtitles-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/run/secrets/sonarr-api";
                hostConfig.urlBase = "/sonarr";
              };
            };
            radarr = {
              enable = true;
              config = {
                apiKey._secret = "/run/secrets/radarr-api";
                hostConfig.urlBase = "/radarr";
              };
            };
            bazarr.enable = true;
          };
        }
      ];
      unit = config.config.systemd.services.bazarr;
      env = unit.environment;
      loadCredentials = unit.serviceConfig.LoadCredential or [ ];
      policy = builtins.fromJSON (builtins.readFile env.BAZARR_POLICY_JSON);
    in
    pkgs.runCommand "unit-test-bazarr-no-opensubtitles-generation" { } ''
      ${check "Bazarr omits OpenSubtitlesCom policy without credentials" (
        policy.requiredProviders == [ ]
        && !(builtins.hasAttr "opensubtitlescom" policy.ownedValues)
        && env.BAZARR_REQUIRE_OPENSUBTITLES == "0"
        && !(builtins.hasAttr "BAZARR_OPENSUBTITLES_USERNAME_FILE" env)
        && !(builtins.hasAttr "BAZARR_OPENSUBTITLES_PASSWORD_FILE" env)
        && lib.elem "sonarr-api-key:/run/secrets/sonarr-api" loadCredentials
        && lib.elem "radarr-api-key:/run/secrets/radarr-api" loadCredentials
        && lib.all (entry: !lib.hasInfix "opensubtitlescom" entry) loadCredentials
      )}

      echo 'PASS: bazarr-no-opensubtitles-generation' > $out
    '';

  bazarr-opensubtitles-partial-credential-assertion =
    let
      partialConfig =
        openSubtitlesCom:
        builtins.tryEval (
          let
            config = evalConfig [
              {
                nixflix = {
                  enable = true;
                  sonarr = {
                    enable = true;
                    config = {
                      apiKey._secret = "/run/secrets/sonarr-api";
                      hostConfig.urlBase = "/sonarr";
                    };
                  };
                  radarr = {
                    enable = true;
                    config = {
                      apiKey._secret = "/run/secrets/radarr-api";
                      hostConfig.urlBase = "/radarr";
                    };
                  };
                  bazarr = {
                    enable = true;
                    inherit openSubtitlesCom;
                  };
                };
              }
            ];
          in
          config.config.system.build.toplevel.drvPath
        );
      usernameOnly = partialConfig {
        username._secret = "/run/secrets/opensubtitlescom-username";
      };
      passwordOnly = partialConfig {
        password._secret = "/run/secrets/opensubtitlescom-password";
      };
    in
    assertTest "bazarr-opensubtitles-partial-credential-assertion" (
      !usernameOnly.success && !passwordOnly.success
    );

  arr-josh-policy-no-prune-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            mediaDir = "/Volumes/Nixflix/media";
            downloadsDir = "/Volumes/Nixflix/downloads";
            mediaPolicy.josh.enable = true;

            downloadarr = {
              services = [
                "radarr"
                "sonarr"
                "prowlarr"
              ];
              deleteUnmanaged = true;
              sabnzbd.enable = true;
              rtorrent.enable = true;
              deluge.enable = true;
              transmission.enable = true;
              extraClients = [
                {
                  enable = true;
                  name = "Unsafe";
                  implementationName = "Transmission";
                }
              ];
            };

            torrentClients.qbittorrent = {
              enable = true;
              downloadsDir = "/Volumes/Nixflix/downloads/torrent";
              password._secret = "/run/secrets/qbit-pass";
              categories = {
                default = "/wrong/default";
                radarr = "/wrong/radarr";
                sonarr = "/wrong/sonarr";
                prowlarr = "/should-not-exist";
              };
            };

            radarr = {
              enable = true;
              mediaDirs = [
                "/Volumes/Nixflix/media/movies"
                "/Volumes/Nixflix/adopted/movies"
              ];
              config = {
                apiKey._secret = "/run/secrets/radarr-api";
                hostConfig.urlBase = "/radarr";
                deleteUnmanagedRootFolders = true;
                deleteUnmanagedDelayProfiles = true;
              };
            };

            sonarr = {
              enable = true;
              mediaDirs = [
                "/Volumes/Nixflix/media/tv"
                "/Volumes/Nixflix/adopted/tv"
              ];
              config = {
                apiKey._secret = "/run/secrets/sonarr-api";
                hostConfig.urlBase = "/sonarr";
                deleteUnmanagedRootFolders = true;
                deleteUnmanagedDelayProfiles = true;
              };
            };

            prowlarr = {
              enable = true;
              config = {
                apiKey._secret = "/run/secrets/prowlarr-api";
                applications = [
                  {
                    name = "Radarr";
                    implementationName = "Radarr";
                    apiKey._secret = "/run/secrets/radarr-api";
                  }
                ];
                indexers = [ { name = "Private Tracker"; } ];
                indexerProxies = [ { name = "FlareSolverr"; } ];
                hostConfig = {
                  urlBase = "/prowlarr";
                  username._secret = "/run/secrets/prowlarr-user";
                  password._secret = "/run/secrets/prowlarr-password";
                };
              };
            };
          };
        }
      ];
      cfg = config.config.nixflix;
      systemdUnits = config.config.systemd.services;
      systemdTargets = config.config.systemd.targets;
      sonarrScripts = [
        systemdUnits.sonarr-rootfolders.script
        systemdUnits.sonarr-delayprofiles.script
        systemdUnits.sonarr-mediamanagement.script
        systemdUnits.sonarr-qualityprofiles.script
        systemdUnits.sonarr-customformats.script
        systemdUnits.sonarr-downloadclients.script
      ];
      radarrScripts = [
        systemdUnits.radarr-rootfolders.script
        systemdUnits.radarr-delayprofiles.script
        systemdUnits.radarr-mediamanagement.script
        systemdUnits.radarr-qualityprofiles.script
        systemdUnits.radarr-customformats.script
        systemdUnits.radarr-downloadclients.script
      ];
      qualityProfileScript = builtins.readFile ../../modules/arr-common/scripts/configure-quality-profiles.sh;
      customFormatScript = builtins.readFile ../../modules/arr-common/scripts/configure-custom-formats.sh;
      allGeneratedScripts = sonarrScripts ++ radarrScripts ++ [
        qualityProfileScript
        customFormatScript
      ];
      sonarrProfiles = cfg.sonarr.config.qualityProfiles;
      radarrProfiles = cfg.radarr.config.qualityProfiles;
      customFormatNames = map (format: format.name) cfg.sonarr.config.customFormats;
      getProfile = name: profiles: lib.findFirst (profile: profile.name == name) null profiles;
      sonarrBest = getProfile "Best" sonarrProfiles;
      sonarrGoodEnough = getProfile "Good Enough" sonarrProfiles;
      radarrBest = getProfile "Best" radarrProfiles;
      radarrGoodEnough = getProfile "Good Enough" radarrProfiles;
      hasThresholds =
        profile:
        profile.minFormatScore == 0
        && profile.cutoffFormatScore == 0
        && profile.minUpgradeFormatScore == 1;
      absentUnit = name: !(builtins.hasAttr name systemdUnits);
      policyTarget = systemdTargets."nixflix-media-policy";
    in
    pkgs.runCommand "unit-test-arr-josh-policy-no-prune-generation" { } ''
      ${check "Josh media policy exposes aggregate systemd target" (
        builtins.hasAttr "nixflix-media-policy" systemdTargets
        && lib.elem "sonarr-qualityprofiles.service" policyTarget.requires
        && lib.elem "sonarr-downloadclients.service" policyTarget.requires
        && lib.elem "radarr-qualityprofiles.service" policyTarget.requires
        && lib.elem "radarr-downloadclients.service" policyTarget.requires
        && !lib.elem "prowlarr-downloadclients.service" policyTarget.requires
      )}
      ${check "Josh media policy limits downloadarr to Sonarr/Radarr" (
        cfg.downloadarr.services == [
          "radarr"
          "sonarr"
        ]
        && !(builtins.hasAttr "prowlarr-downloadclients" systemdUnits)
      )}
      ${check "Josh media policy suppresses Prowlarr mutation units" (
        lib.all absentUnit [
          "prowlarr-applications"
          "prowlarr-config"
          "prowlarr-downloadclients"
          "prowlarr-indexer-proxies"
          "prowlarr-indexers"
          "prowlarr-tags"
        ]
        && cfg.prowlarr.config.applications == [ ]
        && cfg.prowlarr.config.indexers == [ ]
        && cfg.prowlarr.config.indexerProxies == [ ]
        && cfg.prowlarr.config.hostConfig.username == null
        && cfg.prowlarr.config.hostConfig.password == null
      )}
      ${check "Josh media policy keeps Downloadarr qBittorrent-only and no-prune" (
        !cfg.downloadarr.deleteUnmanaged
        && !cfg.downloadarr.sabnzbd.enable
        && !cfg.downloadarr.rtorrent.enable
        && !cfg.downloadarr.deluge.enable
        && !cfg.downloadarr.transmission.enable
        && cfg.downloadarr.extraClients == [ ]
      )}
      ${check "Arr adoption units are generated for Sonarr and Radarr" (
        builtins.hasAttr "sonarr-qualityprofiles" systemdUnits
        && builtins.hasAttr "sonarr-customformats" systemdUnits
        && builtins.hasAttr "sonarr-downloadclients" systemdUnits
        && builtins.hasAttr "radarr-qualityprofiles" systemdUnits
        && builtins.hasAttr "radarr-customformats" systemdUnits
        && builtins.hasAttr "radarr-downloadclients" systemdUnits
      )}
      ${check "Arr adoption scripts omit forbidden tracker/delete paths" (
        lib.all hasNoForbiddenMediaMutations allGeneratedScripts
      )}
      ${check "Arr policy keeps no-prune flags false" (
        !cfg.sonarr.config.deleteUnmanagedRootFolders
        && !cfg.sonarr.config.deleteUnmanagedDelayProfiles
        && !cfg.radarr.config.deleteUnmanagedRootFolders
        && !cfg.radarr.config.deleteUnmanagedDelayProfiles
        && !cfg.downloadarr.deleteUnmanaged
      )}
      ${check "Arr policy owns Best and Good Enough thresholds" (
        hasThresholds sonarrBest
        && hasThresholds sonarrGoodEnough
        && hasThresholds radarrBest
        && hasThresholds radarrGoodEnough
      )}
      ${check "Sonarr policy owns requested quality gates" (
        sonarrBest.cutoff == 19
        && sonarrGoodEnough.cutoff == 7
        && lib.elem "WEB 1080p" sonarrBest.allowedQualities
        && lib.elem "Bluray-1080p Remux" sonarrBest.disallowedQualities
        && lib.elem "Bluray-1080p Remux" sonarrGoodEnough.disallowedQualities
      )}
      ${check "Radarr policy owns requested quality gates" (
        radarrBest.cutoff == 19
        && radarrGoodEnough.cutoff == 7
        && lib.elem "WEB 1080p" radarrBest.allowedQualities
        && lib.elem "Remux-1080p" radarrBest.disallowedQualities
        && lib.elem "Remux-1080p" radarrGoodEnough.disallowedQualities
      )}
      ${check "Arr policy owns custom format definitions and scores" (
        lib.sort (a: b: a < b) customFormatNames
        == [
          "Atmos"
          "Dolby Vision"
          "HDR"
          "HDR10+"
          "Surround 5.1+"
        ]
        && (lib.findFirst (format: format.name == "Dolby Vision") null cfg.sonarr.config.customFormats).scores.Best == 1000
        && (lib.findFirst (format: format.name == "Atmos") null cfg.sonarr.config.customFormats).scores.${"Good Enough"} == 700
      )}
      ${check "qBittorrent policy owns categories and safety defaults" (
        lib.sort (a: b: a < b) (builtins.attrNames cfg.torrentClients.qbittorrent.categories)
        == [
          "default"
          "radarr"
          "sonarr"
        ]
        &&
        cfg.torrentClients.qbittorrent.categories.default == "/Volumes/Nixflix/downloads/torrent/default"
        && cfg.torrentClients.qbittorrent.categories.sonarr == "/Volumes/Nixflix/downloads/torrent/sonarr"
        && cfg.torrentClients.qbittorrent.categories.radarr == "/Volumes/Nixflix/downloads/torrent/radarr"
        && cfg.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Address == "127.0.0.1"
        && !cfg.torrentClients.qbittorrent.serverConfig.BitTorrent.Session.DHTEnabled
        && !cfg.torrentClients.qbittorrent.serverConfig.BitTorrent.Session.LSDEnabled
        && !cfg.torrentClients.qbittorrent.serverConfig.BitTorrent.Session.PeXEnabled
      )}
      echo 'PASS: arr-josh-policy-no-prune-generation' > $out
    '';

  arr-quality-profile-missing-quality-fails =
    pkgs.runCommand "unit-test-arr-quality-profile-missing-quality-fails"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.jq
        ];
      }
      ''
        mkdir -p bin
        cat > bin/curl <<'SH'
        #!${pkgs.bash}/bin/bash
        set -eu
        case " $* " in
          *" -X PUT "*|*" -X POST "*)
            echo "unexpected quality profile mutation" >&2
            exit 99
            ;;
        esac
        cat <<'JSON'
        [
          {
            "id": 19,
            "name": "Ultra-HD",
            "cutoff": 19,
            "items": [
              {
                "quality": {
                  "id": 1,
                  "name": "WEB 1080p"
                },
                "allowed": true
              }
            ]
          }
        ]
        JSON
        SH
        chmod +x bin/curl

        cat > profiles.json <<'JSON'
        [
          {
            "name": "Best",
            "sourceName": "Ultra-HD",
            "disallowedQualities": ["WEB 1080p"]
          },
          {
            "name": "Bad Later Profile",
            "sourceName": "Ultra-HD",
            "disallowedQualities": ["Remux-2160p"]
          }
        ]
        JSON

        export PATH="$PWD/bin:$PATH"
        export ARR_API_KEY=test-key
        if ${pkgs.bash}/bin/bash ${../../modules/arr-common/scripts/configure-quality-profiles.sh} \
          Radarr http://127.0.0.1:7878/radarr/api/v3 profiles.json > out.log 2> err.log; then
          echo "FAIL: missing quality name did not fail" >&2
          exit 1
        fi
        if ! grep -F "missing requested quality names" err.log >/dev/null \
          || ! grep -F "Remux-2160p" err.log >/dev/null; then
          echo "FAIL: missing quality fixture failed for the wrong reason" >&2
          echo "--- stdout ---" >&2
          cat out.log >&2
          echo "--- stderr ---" >&2
          cat err.log >&2
          exit 1
        fi

        echo 'PASS: arr-quality-profile-missing-quality-fails' > $out
      '';

  qbittorrent-category-adoption-merge =
    pkgs.runCommand "unit-test-qbittorrent-category-adoption-merge" { } ''
      mkdir -p state/qBittorrent/config
      cat > state/qBittorrent/config/categories.json <<'JSON'
      {
        "sonarr": {
          "save_path": "/old/sonarr",
          "tags": ["keep"]
        },
        "unmanaged": {
          "save_path": "/keep/unmanaged"
        }
      }
      JSON
      cat > declared.json <<'JSON'
      {
        "default": {
          "save_path": "/Volumes/Nixflix/downloads/torrent/default"
        },
        "sonarr": {
          "save_path": "/Volumes/Nixflix/downloads/torrent/sonarr"
        },
        "radarr": {
          "save_path": "/Volumes/Nixflix/downloads/torrent/radarr"
        }
      }
      JSON

      ${pkgs.python3}/bin/python ${../../modules/torrentClients/qbittorrent-merge-categories.py} \
        state/qBittorrent/config/categories.json declared.json

      ${pkgs.python3}/bin/python - <<'PY'
      import json
      from pathlib import Path

      categories = json.loads(Path("state/qBittorrent/config/categories.json").read_text())
      assert categories["default"]["save_path"] == "/Volumes/Nixflix/downloads/torrent/default"
      assert categories["sonarr"]["save_path"] == "/Volumes/Nixflix/downloads/torrent/sonarr"
      assert categories["sonarr"]["tags"] == ["keep"]
      assert categories["radarr"]["save_path"] == "/Volumes/Nixflix/downloads/torrent/radarr"
      assert categories["unmanaged"]["save_path"] == "/keep/unmanaged"
      PY

      cat > empty-declared.json <<'JSON'
      {
        "prowlarr": {
          "save_path": ""
        }
      }
      JSON
      if ${pkgs.python3}/bin/python ${../../modules/torrentClients/qbittorrent-merge-categories.py} \
        state/qBittorrent/config/categories.json empty-declared.json 2> empty.err; then
        echo "FAIL: qBittorrent category writer accepted an empty save_path" >&2
        exit 1
      fi
      grep -F "non-empty save_path" empty.err >/dev/null

      writer=${../../modules/torrentClients/qbittorrent-merge-categories.py}
      for needle in BT_backup .torrent .fastresume 'shutil.rmtree' 'os.remove'; do
        if grep -F "$needle" "$writer" >/dev/null; then
          echo "FAIL: qBittorrent category writer touches $needle" >&2
          exit 1
        fi
      done

      echo 'PASS: qbittorrent-category-adoption-merge' > $out
    '';

  jellyfin-plugin-package-service-generation =
    let
      plugin = pkgs.runCommand "test-plugin-1.0.0" { } ''
        mkdir -p "$out"
        touch "$out/TestPlugin.dll"
      '';
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              plugins."Test Plugin".package = plugin;
              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };
            };
          };
        }
      ];
      systemdUnits = config.config.systemd.services;
      tmpfilesSettings = config.config.systemd.tmpfiles.settings;
      pluginPath = "${config.config.nixflix.jellyfin.dataDir}/plugins";
    in
    pkgs.runCommand "unit-test-jellyfin-plugin-package-service-generation" { } ''
      ${check "plugin service exists" (systemdUnits ? jellyfin-plugins)}
      ${check "plugin tmpfiles directory exists" (
        builtins.hasAttr pluginPath tmpfilesSettings."10-jellyfin"
      )}

      echo 'PASS: jellyfin-plugin-package-service-generation' > $out
    '';

  jellyfin-plugin-source-assertion =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;

                jellyfin = {
                  enable = true;
                  plugins."Broken Plugin" = {
                    package = {
                      version = "1.0.0.0";
                    };
                    config.SomeSetting = true;
                  };
                  users.admin = {
                    password = "testpassword";
                    policy.isAdministrator = true;
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "jellyfin-plugin-source-assertion" (!result.success);

  jellyfin-plugin-repo-service-generation =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              plugins.Bookshelf = {
                package = jellyfinPlugins.fromRepo {
                  version = "latest";
                  hash = "sha256-16jaQRh1rIFE27nSSEWNF7UjVsPJDaRf24Ews0BZGas=";
                };
              };
              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };
            };
          };
        }
      ];
      pluginService = config.config.systemd.services.jellyfin-plugins;
    in
    pkgs.runCommand "unit-test-jellyfin-plugin-repo-service-generation" { } ''
      ${check "plugin service exists for repo-managed plugin" (
        config.config.systemd.services ? jellyfin-plugins
      )}
      ${check "repo-managed plugins resolve to package sync commands" (
        lib.hasInfix "Syncing packaged plugin: Bookshelf" pluginService.script
      )}
      ${check "resolved plugin directory name appears in service script" (
        lib.hasInfix "Bookshelf_13.0.0.0" pluginService.script
      )}

      echo 'PASS: jellyfin-plugin-repo-service-generation' > $out
    '';

  jellyfin-plugin-repo-ambiguity-assertion =
    let
      targetAbi = "${pkgs.jellyfin.version}.0";
      manifestA = pkgs.writeText "jellyfin-plugin-repo-a.json" (
        builtins.toJSON [
          {
            guid = "11111111-1111-1111-1111-111111111111";
            name = "Collision Plugin";
            versions = [
              {
                version = "1.0.0.0";
                inherit targetAbi;
                sourceUrl = "https://example.invalid/repo-a.zip";
              }
            ];
          }
        ]
      );
      manifestB = pkgs.writeText "jellyfin-plugin-repo-b.json" (
        builtins.toJSON [
          {
            guid = "22222222-2222-2222-2222-222222222222";
            name = "Collision Plugin";
            versions = [
              {
                version = "1.0.0.0";
                inherit targetAbi;
                sourceUrl = "https://example.invalid/repo-b.zip";
              }
            ];
          }
        ]
      );
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;

                jellyfin = {
                  enable = true;
                  apiKey = "test-api-key";
                  system.pluginRepositories = lib.mkForce {
                    "Repo A" = {
                      url = builtins.unsafeDiscardStringContext "file://${manifestA}";
                      hash = manifestHash manifestA;
                      enabled = true;
                    };
                    "Repo B" = {
                      url = builtins.unsafeDiscardStringContext "file://${manifestB}";
                      hash = manifestHash manifestB;
                      enabled = true;
                    };
                  };
                  plugins."Collision Plugin" = {
                    package = jellyfinPlugins.fromRepo {
                      version = "1.0.0.0";
                      hash = lib.fakeHash;
                    };
                  };
                  users.admin = {
                    password = "testpassword";
                    policy.isAdministrator = true;
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "jellyfin-plugin-repo-ambiguity-assertion" (!result.success);

  jellyfin-integration =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };
            };

            radarr = {
              enable = true;
              mediaDirs = [ "/media/movies" ];
              config = {
                hostConfig = {
                  port = 7878;
                  username = "admin";
                  password._secret = "/run/secrets/radarr-pass";
                };
                apiKey._secret = "/run/secrets/radarr-api";
                rootFolders = [ { path = "/media/movies"; } ];
              };
            };

            sonarr = {
              enable = true;
              mediaDirs = [ "/media/shows" ];
              config = {
                hostConfig = {
                  port = 8989;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
                apiKey._secret = "/run/secrets/sonarr-api";
                rootFolders = [ { path = "/media/shows"; } ];
              };
            };

            sonarr-anime = {
              enable = true;
              mediaDirs = [ "/media/anime" ];
              config = {
                hostConfig = {
                  port = 8990;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-anime-pass";
                };
                apiKey._secret = "/run/secrets/sonarr-anime-api";
                rootFolders = [ { path = "/media/anime"; } ];
              };
            };

            lidarr = {
              enable = true;
              mediaDirs = [ "/media/music" ];
              config = {
                hostConfig = {
                  port = 8686;
                  username = "admin";
                  password._secret = "/run/secrets/lidarr-pass";
                };
                apiKey._secret = "/run/secrets/lidarr-api";
                rootFolders = [ { path = "/media/music"; } ];
              };
            };
          };
        }
      ];

      inherit (config.config.nixflix.jellyfin) libraries;
    in
    pkgs.runCommand "unit-test-jellyfin-integration" { } ''
      ${check "Movies library exists" (libraries ? Movies)}
      ${check "Movies library has correct collectionType" (libraries.Movies.collectionType == "movies")}
      ${check "Movies library has correct path" (builtins.elem "/media/movies" libraries.Movies.paths)}

      ${check "Shows library exists" (libraries ? Shows)}
      ${check "Shows library has correct collectionType" (libraries.Shows.collectionType == "tvshows")}
      ${check "Shows library has correct path" (builtins.elem "/media/shows" libraries.Shows.paths)}

      ${check "Anime library exists" (libraries ? Anime)}
      ${check "Anime library has correct collectionType" (libraries.Anime.collectionType == "tvshows")}
      ${check "Anime library has correct path" (builtins.elem "/media/anime" libraries.Anime.paths)}

      ${check "Music library exists" (libraries ? Music)}
      ${check "Music library has correct collectionType" (libraries.Music.collectionType == "music")}
      ${check "Music library has correct path" (builtins.elem "/media/music" libraries.Music.paths)}

      echo 'PASS: jellyfin-integration' > $out
    '';

  download-clients-no-reverse-proxy =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            nginx.enable = false;

            radarr = {
              enable = true;
              config = {
                hostConfig = {
                  port = 7878;
                  username = "admin";
                  password._secret = "/run/secrets/radarr-pass";
                };
                apiKey._secret = "/run/secrets/radarr-api";
                rootFolders = [ { path = "/media/movies"; } ];
              };
            };

            usenetClients.sabnzbd = {
              enable = true;
              settings.misc = {
                api_key._secret = pkgs.writeText "sabnzbd-apikey" "testapikey123456789abcdef";
                nzb_key._secret = pkgs.writeText "sabnzbd-nzbkey" "testnzbkey123456789abcdef";
                port = 8080;
                url_base = "/sabnzbd";
              };
            };
          };
        }
      ];
      radarrCfg = config.config.nixflix.radarr;
      sabnzbdCfg = config.config.nixflix.usenetClients.sabnzbd;
      downloadClientsService = config.config.systemd.services."radarr-downloadclients";
    in
    pkgs.runCommand "unit-test-download-clients-no-reverse-proxy" { } ''
      ${check "radarr bindAddress is 0.0.0.0 when nginx is disabled" (
        radarrCfg.config.hostConfig.bindAddress == "0.0.0.0"
      )}
      ${check "radarr connectionAddress is 127.0.0.1 (not 0.0.0.0)" (
        radarrCfg.connectionAddress == "127.0.0.1"
      )}
      ${check "sabnzbd connectionAddress is 127.0.0.1 (not 0.0.0.0)" (
        sabnzbdCfg.connectionAddress == "127.0.0.1"
      )}
      ${check "radarr-downloadclients ExecStartPre uses connectionAddress" (
        lib.hasInfix "127.0.0.1" downloadClientsService.serviceConfig.ExecStartPre
      )}
      ${check "radarr-downloadclients ExecStartPre does not use 0.0.0.0" (
        !lib.hasInfix "0.0.0.0" downloadClientsService.serviceConfig.ExecStartPre
      )}
      ${check "radarr-downloadclients script uses connectionAddress" (
        lib.hasInfix "127.0.0.1" downloadClientsService.script
      )}
      ${check "radarr-downloadclients script does not use 0.0.0.0" (
        !lib.hasInfix "0.0.0.0" downloadClientsService.script
      )}
      echo 'PASS: download-clients-no-reverse-proxy' > $out
    '';

  jellyfin-subtitles =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;

            jellyfin = {
              enable = true;
              apiKey = "test-api-key";

              users.admin = {
                password = "testpassword";
                policy.isAdministrator = true;
              };

              plugins = {
                "Open Subtitles" = {
                  enable = true;
                  config = {
                    Username = "testsubsuser";
                    Password = "opensubs_test_password";
                  };
                };

                subbuzz = {
                  enable = true;
                  config = {
                    EnableOpenSubtitles = true;
                    EnableYifySubtitles = true;
                    MinScore = 60;
                    Cache.SubLifeInMinutes = "Always";
                    SubPostProcessing.EncodeSubtitlesToUTF8 = false;
                  };
                };

                "Subtitle Extract" = {
                  enable = true;
                  config = {
                    ExtractionDuringLibraryScan = true;
                    IncludeTextSubtitles = true;
                    IncludeGraphicalSubtitles = false;
                  };
                };
              };

              libraries."Subtitle Movies" = {
                collectionType = "movies";
                paths = [ "/media/movies" ];
                subtitleFetcherOrder = [
                  "Open Subtitles"
                  "subbuzz"
                ];
                subtitleDownloadLanguages = [
                  "eng"
                  "spa"
                ];
                saveSubtitlesWithMedia = true;
                allowEmbeddedSubtitles = "AllowAll";
                requirePerfectSubtitleMatch = true;
                skipSubtitlesIfAudioTrackMatches = false;
                skipSubtitlesIfEmbeddedSubtitlesPresent = true;
              };
            };
          };
        }
      ];
      pluginService = config.config.systemd.services.jellyfin-plugins;
      jellyfinCfg = config.config.nixflix.jellyfin;
    in
    pkgs.runCommand "unit-test-jellyfin-subtitles" { } ''
      ${check "jellyfin-plugins service exists" (config.config.systemd.services ? jellyfin-plugins)}

      ${check "Open Subtitles plugin sync command in service script" (
        lib.hasInfix "Syncing packaged plugin: Open Subtitles" pluginService.script
      )}
      ${check "subbuzz plugin sync command in service script" (
        lib.hasInfix "Syncing packaged plugin: subbuzz" pluginService.script
      )}
      ${check "Subtitle Extract plugin sync command in service script" (
        lib.hasInfix "Syncing packaged plugin: Subtitle Extract" pluginService.script
      )}

      ${check "Open Subtitles plugin directory name in service script" (
        lib.hasInfix "Open Subtitles_24.0.0.0" pluginService.script
      )}
      ${check "subbuzz plugin directory name in service script" (
        lib.hasInfix "subbuzz_1.4.1.0" pluginService.script
      )}
      ${check "Subtitle Extract plugin directory name in service script" (
        lib.hasInfix "Subtitle Extract_7.0.0.0" pluginService.script
      )}

      ${check "SubBuzz plugin repository is added when subbuzz is enabled" (
        jellyfinCfg.system.pluginRepositories ? "SubBuzz"
      )}

      ${check "subbuzz EnableOpenSubtitles config value" jellyfinCfg.plugins.subbuzz.config.EnableOpenSubtitles}
      ${check "subbuzz EnableYifySubtitles config value" jellyfinCfg.plugins.subbuzz.config.EnableYifySubtitles}
      ${check "subbuzz MinScore config value" (jellyfinCfg.plugins.subbuzz.config.MinScore == 60)}
      ${check "subbuzz Cache.SubLifeInMinutes is 1000001 when set to Always" (
        jellyfinCfg.plugins.subbuzz.config.Cache.SubLifeInMinutes == 1000001
      )}
      ${check "subbuzz SubPostProcessing.EncodeSubtitlesToUTF8 config value" (
        !jellyfinCfg.plugins.subbuzz.config.SubPostProcessing.EncodeSubtitlesToUTF8
      )}

      ${check "Open Subtitles Username config value" (
        jellyfinCfg.plugins."Open Subtitles".config.Username == "testsubsuser"
      )}

      ${check "Subtitle Extract ExtractionDuringLibraryScan config value"
        jellyfinCfg.plugins."Subtitle Extract".config.ExtractionDuringLibraryScan
      }
      ${check "Subtitle Extract IncludeTextSubtitles config value"
        jellyfinCfg.plugins."Subtitle Extract".config.IncludeTextSubtitles
      }
      ${check "Subtitle Extract IncludeGraphicalSubtitles config value" (
        !jellyfinCfg.plugins."Subtitle Extract".config.IncludeGraphicalSubtitles
      )}

      ${check "Subtitle Movies library exists" (jellyfinCfg.libraries ? "Subtitle Movies")}
      ${check "Library subtitle fetcher order" (
        jellyfinCfg.libraries."Subtitle Movies".subtitleFetcherOrder == [
          "Open Subtitles"
          "subbuzz"
        ]
      )}
      ${check "Library subtitle download languages" (
        builtins.elem "eng" jellyfinCfg.libraries."Subtitle Movies".subtitleDownloadLanguages
        && builtins.elem "spa" jellyfinCfg.libraries."Subtitle Movies".subtitleDownloadLanguages
      )}
      ${check "Library saveSubtitlesWithMedia"
        jellyfinCfg.libraries."Subtitle Movies".saveSubtitlesWithMedia
      }
      ${check "Library allowEmbeddedSubtitles" (
        jellyfinCfg.libraries."Subtitle Movies".allowEmbeddedSubtitles == "AllowAll"
      )}
      ${check "Library requirePerfectSubtitleMatch"
        jellyfinCfg.libraries."Subtitle Movies".requirePerfectSubtitleMatch
      }
      ${check "Library skipSubtitlesIfEmbeddedSubtitlesPresent"
        jellyfinCfg.libraries."Subtitle Movies".skipSubtitlesIfEmbeddedSubtitlesPresent
      }
      ${check "Library skipSubtitlesIfAudioTrackMatches" (
        !jellyfinCfg.libraries."Subtitle Movies".skipSubtitlesIfAudioTrackMatches
      )}

      echo 'PASS: jellyfin-subtitles' > $out
    '';

  # LoadCredential replaces the old -env root service; verify the generated unit
  arr-load-credential =
    let
      config = evalConfig [
        {
          nixflix = {
            enable = true;
            sonarr = {
              enable = true;
              config = {
                apiKey._secret = "/run/secrets/sonarr-api";
                hostConfig = {
                  port = 8989;
                  username = "admin";
                  password._secret = "/run/secrets/sonarr-pass";
                };
              };
            };
          };
        }
      ];
      services = config.config.systemd.services;
      svc = services.sonarr.serviceConfig;
    in
    pkgs.runCommand "unit-test-arr-load-credential" { } ''
      ${check "sonarr-env service no longer exists" (!services ? sonarr-env)}
      ${check "LoadCredential set for secret-ref apiKey" (
        builtins.elem "apiKey:/run/secrets/sonarr-api" svc.LoadCredential
      )}
      ${check "no EnvironmentFile" (!svc ? EnvironmentFile)}
      echo 'PASS: arr-load-credential' > $out
    '';

  # hostConfig assertion: username and password must both be set or both be null
  hostconfig-username-requires-password =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                sonarr = {
                  enable = true;
                  config.hostConfig = {
                    port = 8989;
                    username = "admin";
                    # password left at default null
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "hostconfig-username-requires-password" (!result.success);

  hostconfig-password-requires-username =
    let
      result = builtins.tryEval (
        let
          config = evalConfig [
            {
              nixflix = {
                enable = true;
                sonarr = {
                  enable = true;
                  config.hostConfig = {
                    port = 8989;
                    username = null;
                    password._secret = "/run/secrets/sonarr-pass";
                  };
                };
              };
            }
          ];
        in
        config.config.system.build.toplevel.drvPath
      );
    in
    assertTest "hostconfig-password-requires-username" (!result.success);

}
