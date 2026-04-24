{
  config,
  lib,
  ...
}:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  hasSabnzbd = config.nixflix ? usenetClients && config.nixflix.usenetClients ? sabnzbd;

  categoriesOption = mkOption {
    type = types.submodule {
      options = {
        radarr = mkOption {
          type = types.str;
          default = "radarr";
          description = "The categories to use for the Radarr instance";
        };

        sonarr = mkOption {
          type = types.str;
          default = "sonarr";
          description = "The categories to use for the Sonarr instance";
        };

        sonarr-anime = mkOption {
          type = types.str;
          default = "sonarr-anime";
          description = "The categories to use for the Sonarr Anime instance";
        };

        lidarr = mkOption {
          type = types.str;
          default = "lidarr";
          description = "The categories to use for the Lidarr instance";
        };

        prowlarr = mkOption {
          type = types.str;
          default = "prowlarr";
          description = "The categories to use for the Prowlarr instance";
        };
      };
    };

    default = { };
    description = "Categories per Starr service instance";
  };

  mkDownloadClientType =
    {
      implementationName,
      enable ? { },
      dependencies ? { },
      host ? { },
      port ? { },
      urlBase ? { },
      extraOptions ? { },
    }:
    types.submodule {
      freeformType = types.attrsOf types.anything;
      options = {
        enable = mkOption (
          {
            type = types.bool;
            default = false;
            description = "Whether or not this download client is enabled.";
          }
          // enable
        );

        dependencies = mkOption (
          {
            type = types.listOf types.str;
            default = [ ];
            description = "Backend-managed runtime dependencies that this integration waits for before configuration.";
          }
          // dependencies
        );

        name = mkOption {
          type = types.str;
          default = implementationName;
          description = "User-defined name for the download client instance.";
        };

        implementationName = mkOption {
          type = types.str;
          readOnly = true;
          default = implementationName;
          description = "Type of download client to configure (matches schema implementationName).";
        };

        host = mkOption (
          {
            type = types.str;
            description = "Host of the download client.";
            default = "127.0.0.1";
            example = "example.com";
          }
          // host
        );

        port = mkOption (
          {
            type = types.port;
            description = "Port of the download client.";
            default = 8080;
          }
          // port
        );

        urlBase = mkOption (
          {
            type = types.str;
            description = "Adds a prefix to the ${implementationName} url, such as http://[host]:[port]/[urlBase].";
            default = "";
          }
          // urlBase
        );

        categories = categoriesOption;
      }
      // extraOptions;
    };

  sabnzbdType = mkDownloadClientType {
    implementationName = "SABnzbd";

    enable = {
      default = if hasSabnzbd then config.nixflix.usenetClients.sabnzbd.enable else false;
      defaultText = literalExpression ''
        if config.nixflix ? usenetClients && config.nixflix.usenetClients ? sabnzbd then
          config.nixflix.usenetClients.sabnzbd.enable
        else
          false
      '';
    };

    dependencies.default =
      if config.nixflix.runtime ? downloadClients && config.nixflix.runtime.downloadClients ? sabnzbd then
        config.nixflix.runtime.downloadClients.sabnzbd.dependencies
      else
        [ ];
    dependencies.defaultText = literalExpression ''
      if config.nixflix.runtime ? downloadClients && config.nixflix.runtime.downloadClients ? sabnzbd then
        config.nixflix.runtime.downloadClients.sabnzbd.dependencies
      else
        [ ]
    '';

    port = {
      default = if hasSabnzbd then config.nixflix.usenetClients.sabnzbd.settings.misc.port else 8080;
      defaultText = literalExpression ''
        if config.nixflix ? usenetClients && config.nixflix.usenetClients ? sabnzbd then
          config.nixflix.usenetClients.sabnzbd.settings.misc.port
        else
          8080
      '';
      example = 8080;
    };

    urlBase = {
      default =
        if !hasSabnzbd then
          ""
        else if config.nixflix.usenetClients.sabnzbd.settings.misc.url_base == "" then
          ""
        else
          lib.removePrefix "/" config.nixflix.usenetClients.sabnzbd.settings.misc.url_base;
      defaultText = literalExpression ''
        if !(config.nixflix ? usenetClients && config.nixflix.usenetClients ? sabnzbd) then
          ""
        else if config.nixflix.usenetClients.sabnzbd.settings.misc.url_base == "" then
          ""
        else
          lib.removePrefix "/" config.nixflix.usenetClients.sabnzbd.settings.misc.url_base;
      '';
      example = "/sabnzbd";
    };

    extraOptions = {
      apiKey = secrets.mkSecretOption {
        description = "API key for the download client.";
        default = if hasSabnzbd then config.nixflix.usenetClients.sabnzbd.settings.misc.api_key else null;
        defaultText = literalExpression ''
          if config.nixflix ? usenetClients && config.nixflix.usenetClients ? sabnzbd then
            config.nixflix.usenetClients.sabnzbd.settings.misc.api_key
          else
            null
        '';
        nullable = true;
      };
    };
  };

  qbittorrentType = mkDownloadClientType {
    implementationName = "qBittorrent";

    enable = {
      default = config.nixflix.torrentClients.qbittorrent.enable;
      defaultText = literalExpression "config.nixflix.torrentClients.qbittorrent.enable";
    };

    dependencies.default = config.nixflix.runtime.downloadClients.qbittorrent.dependencies;
    dependencies.defaultText = literalExpression "config.nixflix.runtime.downloadClients.qbittorrent.dependencies";

    port = {
      default = config.nixflix.runtime.downloadClients.qbittorrent.port;
      defaultText = literalExpression "config.nixflix.runtime.downloadClients.qbittorrent.port";
      example = 8080;
    };

    urlBase = {
      example = "qbittorrent";
    };

    extraOptions = {
      username = secrets.mkSecretOption {
        description = "Username key for the download client.";
        default = config.nixflix.runtime.downloadClients.qbittorrent.username;
        defaultText = literalExpression "config.nixflix.runtime.downloadClients.qbittorrent.username";
      };

      password = secrets.mkSecretOption {
        description = "Password for the download client.";
        default = config.nixflix.torrentClients.qbittorrent.password;
        defaultText = literalExpression "config.nixflix.torrentClients.qbittorrent.password";
      };
    };
  };

  rtorrentType = mkDownloadClientType {
    implementationName = "rTorrent";

    port = {
      description = "Port of the download client. This competes with SABnzbd.";
    };

    urlBase = {
      description = ''
        Path to the XMLRPC endpoint, see http(s)://[host]:[port]/[urlPath].
        This is usually RPC2 or [path to ruTorrent]/plugins/rpc/rpc.php when using ruTorrent.
      '';
      default = "RPC2";
      example = "rtorrent/RPC2";
    };

    extraOptions = {
      username = secrets.mkSecretOption {
        description = "Username key for the download client.";
      };

      password = secrets.mkSecretOption {
        description = "Password for the download client.";
      };
    };
  };

  transmissionType = mkDownloadClientType {
    implementationName = "Transmission";

    port.default = 9091;

    urlBase = {
      description = ''
        Adds a prefix to the Transmission rpc url, eg http://[host]:[port]/[urlBase]/rpc
      '';
      default = "/transmission/";
    };

    extraOptions = {
      username = secrets.mkSecretOption {
        description = "Username key for the download client.";
      };

      password = secrets.mkSecretOption {
        description = "Password for the download client.";
      };
    };
  };

  delugeType = mkDownloadClientType {
    implementationName = "Deluge";

    port.default = 8112;

    urlBase = {
      description = ''
        Adds a prefix to the deluge json url, see http://[host]:[port]/[urlBase]/json
      '';
      default = "";
      example = "deluge";
    };

    extraOptions = {
      password = secrets.mkSecretOption {
        description = "Password for the download client.";
      };
    };
  };
in
{
  options.nixflix.downloadarr = mkOption {
    type = types.submodule {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable Downloadarr.";

        };
        sabnzbd = mkOption {
          type = sabnzbdType;
          default = { };
          description = "SABnzbd download client definition for Starr services.";
        };

        qbittorrent = mkOption {
          type = qbittorrentType;
          default = { };
          description = "qBittorrent download client definition for Starr services.";
        };

        rtorrent = mkOption {
          type = rtorrentType;
          default = { };
          description = "rTorrent download client definition for Starr services.";
        };

        deluge = mkOption {
          type = delugeType;
          default = { };
          description = "Deluge download client definition for Starr services.";
        };

        transmission = mkOption {
          type = transmissionType;
          default = { };
          description = "Transmission Deluge download client definition for Starr services.";
        };

        extraClients = mkOption {
          type = types.listOf (types.attrsOf types.anything);
          default = [ ];
          description = ''
            For more clients or if you have more than one instance of a specific client.
            Follows the same schema general schema as the other options. `implementationName` is a required field.

            A list of implementation names can be acquired with:

            ```sh
            curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/api_key>)" "http://127.0.0.1:9696/prowlarr/api/v1/downloadclient/schema" | jq '.[].implementationName'`
            ```

            You can run the following command to get the field names for a particular `implementationName`:

            ```sh
            curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/apiKey>)" "http://127.0.0.1:9696/prowlarr/api/v1/downloadclient/schema" | jq '.[] | select(.implementationName=="<indexerName>") | .fields'
            ```

            Or if you have nginx disabled or `config.nixflix.prowlarr.config.hostConfig.urlBase` is not configured

            ```sh
            curl -s -H "X-Api-Key: $(sudo cat </path/to/prowlarr/apiKey>)" "http://127.0.0.1:9696/api/v1/indexer/schema" | jq '.[] | select(.implementationName=="<indexerName>") | .fields'
            ```
          '';
        };
      };
    };
    default = { };
    description = ''
      Downloadarr is a service that is responsible for configuring Starr services with download clients.
      When you enable the service for that client to run, Downloadarr integrates it automatically with each Starr service.

      The list is small right now. However, Downloadarr itself supports supports more integrations than Nixflix supports.
      It just has less magic built in.

      Each module is currently only a subset of the options available. You can add more options reqresented
      in the UI if you know their keys.
    '';
  };
}
