{
  config,
  lib,
  ...
}:
with lib;
let
  nixflix = config.nixflix;
  cfg = nixflix.mediaPolicy.josh;
  torrentRoot = nixflix.torrentClients.qbittorrent.downloadsDir;
  formatScores = {
    Best = 0;
    "Good Enough" = 0;
  };
  scoreThresholds = {
    minFormatScore = 0;
    cutoffFormatScore = 0;
    minUpgradeFormatScore = 1;
  };
  scoredFormat = name: value: scores: {
    inherit name scores;
    includeCustomFormatWhenRenaming = false;
    specifications = [
      {
        inherit name;
        implementation = "ReleaseTitleSpecification";
        implementationName = "Release Title";
        negate = false;
        required = false;
        fields = [
          {
            name = "value";
            value = value;
          }
        ];
      }
    ];
  };
  preferredFormats = [
    (scoredFormat "Dolby Vision" "\\b(dv|dovi|dolby[ ._-]?vision)\\b" (
      formatScores
      // {
        Best = 1000;
        "Good Enough" = 1000;
      }
    ))
    (scoredFormat "HDR" "\\b(hdr|hdr10|hdr10\\+|hdr10plus|hlg)\\b" (
      formatScores
      // {
        Best = 500;
        "Good Enough" = 500;
      }
    ))
    (scoredFormat "HDR10+" "\\b(hdr10\\+|hdr10plus)\\b" (
      formatScores
      // {
        Best = 100;
        "Good Enough" = 100;
      }
    ))
    (scoredFormat "Atmos" "\\b(atmos|truehd[ ._-]?atmos|dd\\+?[ ._-]?atmos|eac3[ ._-]?atmos)\\b" (
      formatScores
      // {
        Best = 700;
        "Good Enough" = 700;
      }
    ))
    (scoredFormat "Surround 5.1+" "DTS.?(HD|ES|X(?!\\D))|TRUEHD|ATMOS|DD(\\+|P).?([5-9])|EAC3.?([5-9])"
      (
        formatScores
        // {
          Best = 250;
          "Good Enough" = 250;
        }
      )
    )
  ];
  commonProfileFields = {
    upgradeAllowed = true;
  }
  // scoreThresholds;
  commonMediaManagement = {
    recycleBin = "";
    recycleBinCleanupDays = 7;
    downloadPropersAndRepacks = "preferAndUpgrade";
    deleteEmptyFolders = false;
    fileDate = "none";
    rescanAfterRefresh = "always";
    setPermissionsLinux = false;
    chmodFolder = "755";
    chownGroup = "";
    skipFreeSpaceCheckWhenImporting = false;
    minimumFreeSpaceWhenImporting = 100;
    copyUsingHardlinks = true;
    importExtraFiles = false;
    extraFileExtensions = "srt";
    enableMediaInfo = true;
  };
  defaultDelayProfile = {
    id = 1;
    enableUsenet = true;
    enableTorrent = true;
    preferredProtocol = "torrent";
    usenetDelay = 0;
    torrentDelay = 0;
    bypassIfHighestQuality = true;
    bypassIfAboveCustomFormatScore = false;
    minimumCustomFormatScore = 0;
    order = 2147483647;
    tags = [ ];
  };
  policyTargetName = "nixflix-media-policy";
  policyUnitNames = [
    "radarr-config"
    "radarr-rootfolders"
    "radarr-delayprofiles"
    "radarr-mediamanagement"
    "radarr-qualityprofiles"
    "radarr-customformats"
    "radarr-downloadclients"
    "sonarr-config"
    "sonarr-rootfolders"
    "sonarr-delayprofiles"
    "sonarr-mediamanagement"
    "sonarr-qualityprofiles"
    "sonarr-customformats"
    "sonarr-downloadclients"
    "seerr-request-first-policy"
  ];
  enabledPolicyUnits =
    map (name: "${name}.service") (
      filter (
        name: builtins.hasAttr name config.systemd.services && (config.systemd.services.${name}.enable or true)
      ) policyUnitNames
    );
in
{
  options.nixflix.mediaPolicy.josh = {
    enable = mkEnableOption ''
      Josh's request-first media policy for Seerr/Bazarr/Sonarr/Radarr/qBittorrent
    '';

    systemdTarget = mkOption {
      type = types.str;
      readOnly = true;
      default = "${policyTargetName}.target";
      description = "Aggregate systemd target that completes after generated Josh media policy units.";
    };
  };

  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.targets.${policyTargetName} = {
      description = "Nixflix Josh media policy convergence";
      wantedBy = [ "multi-user.target" ];
      requires = enabledPolicyUnits;
      after = enabledPolicyUnits;
    };

    nixflix = {
      downloadarr = {
        enable = mkDefault true;
        services = mkForce [
          "radarr"
          "sonarr"
        ];
        deleteUnmanaged = mkForce false;
        sabnzbd.enable = mkForce false;
        rtorrent.enable = mkForce false;
        deluge.enable = mkForce false;
        transmission.enable = mkForce false;
        extraClients = mkForce [ ];
      };

      torrentClients.qbittorrent = {
        categories = mkForce {
          default = "${torrentRoot}/default";
          radarr = "${torrentRoot}/radarr";
          sonarr = "${torrentRoot}/sonarr";
        };
        serverConfig = {
          BitTorrent.Session = {
            AnonymousModeEnabled = mkDefault false;
            DHTEnabled = mkDefault false;
            DefaultSavePath = mkDefault "${torrentRoot}/default";
            LSDEnabled = mkDefault false;
            PeXEnabled = mkDefault false;
            QueueingSystemEnabled = mkDefault false;
            TempPath = mkDefault "${torrentRoot}/incomplete";
            TempPathEnabled = mkDefault true;
          };
          Preferences.WebUI = {
            Address = mkDefault "127.0.0.1";
            LocalHostAuth = mkDefault false;
            Username = mkDefault "admin";
          };
        };
      };

      sonarr = {
        settings.indexer.rssSyncInterval = mkDefault 0;
        config = {
          deleteUnmanagedRootFolders = mkForce false;
          deleteUnmanagedDelayProfiles = mkForce false;
          delayProfiles = mkDefault [ defaultDelayProfile ];
          mediaManagement = commonMediaManagement // {
            autoUnmonitorPreviouslyDownloadedEpisodes = false;
            createEmptySeriesFolders = false;
            episodeTitleRequired = "always";
          };
          qualityProfiles = mkDefault [
            ({
              name = "Best";
              sourceName = "Ultra-HD";
              cutoff = 19;
              allowedQualities = [
                "WEB 1080p"
                "WEBDL-1080p"
                "WEBRip-1080p"
                "Bluray-1080p"
              ];
              disallowedQualities = [
                "Bluray-2160p Remux"
                "Bluray-1080p Remux"
              ];
            }
            // commonProfileFields)
            ({
              name = "Good Enough";
              sourceName = "HD-1080p";
              cutoff = 7;
              disallowedQualities = [ "Bluray-1080p Remux" ];
            }
            // commonProfileFields)
          ];
          customFormats = mkDefault preferredFormats;
        };
      };

      radarr = {
        settings.indexer.rssSyncInterval = mkDefault 0;
        config = {
          deleteUnmanagedRootFolders = mkForce false;
          deleteUnmanagedDelayProfiles = mkForce false;
          delayProfiles = mkDefault [ defaultDelayProfile ];
          mediaManagement = commonMediaManagement // {
            autoUnmonitorPreviouslyDownloadedMovies = false;
            createEmptyMovieFolders = false;
          };
          qualityProfiles = mkDefault [
            ({
              name = "Best";
              sourceName = "Ultra-HD";
              cutoff = 19;
              allowedQualities = [
                "WEB 1080p"
                "WEBDL-1080p"
                "WEBRip-1080p"
                "Bluray-1080p"
              ];
              disallowedQualities = [
                "Remux-2160p"
                "Remux-1080p"
              ];
            }
            // commonProfileFields)
            ({
              name = "Good Enough";
              sourceName = "HD-1080p";
              cutoff = 7;
              disallowedQualities = [ "Remux-1080p" ];
            }
            // commonProfileFields)
          ];
          customFormats = mkDefault preferredFormats;
        };
      };

      prowlarr.config = {
        applications = mkForce [ ];
        indexers = mkForce [ ];
        indexerProxies = mkForce [ ];
        hostConfig = {
          username = mkForce null;
          password = mkForce null;
        };
      };
    };
  };
}
