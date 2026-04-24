{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.torrentClients.qbittorrent;
  service = config.services.qbittorrent;
  hostname = "${cfg.subdomain}.${config.nixflix.nginx.domain}";
  categoriesJson = builtins.toJSON (lib.mapAttrs (_name: path: { save_path = path; }) cfg.categories);
  categoriesFile = pkgs.writeText "categories.json" categoriesJson;
  configPath = "${service.profileDir}/qBittorrent/config";
in
{
  config = mkIf (config.nixflix.enable && cfg.enable) {
    services.qbittorrent = builtins.removeAttrs cfg [
      "password"
      "subdomain"
      "downloadsDir"
      "categories"
    ];

    nixflix.runtime.downloadClients.qbittorrent.dependencies = [ "qbittorrent.service" ];

    users = {
      users.${service.user} = mkForce {
        inherit (service) group;
        isSystemUser = true;
        uid = config.nixflix.globals.uids.qbittorrent;
      };

      groups.${service.group} = mkForce { };
    };

    systemd.tmpfiles.settings."10-qbittorrent" = {
      ${service.profileDir}.d = {
        inherit (service) user group;
        mode = "0755";
      };
      ${configPath}.d = {
        inherit (service) user group;
        mode = "0754";
      };
      ${cfg.downloadsDir}.d = {
        inherit (service) user group;
        mode = "0775";
      };
      ${cfg.serverConfig.BitTorrent.Session.DefaultSavePath}.d = {
        inherit (service) user group;
        mode = "0775";
      };
    }
    // lib.mapAttrs' (
      _name: path:
      lib.nameValuePair path {
        d = {
          inherit (service) user group;
          mode = "0775";
        };
      }
    ) (lib.filterAttrs (_name: path: path != "") cfg.categories);

    systemd.services.qbittorrent = {
      after = [ "nixflix-setup-dirs.service" ];
      requires = [ "nixflix-setup-dirs.service" ];
      preStart = lib.mkIf (cfg.categories != { }) (
        lib.mkAfter ''
          cp -f '${categoriesFile}' '${configPath}/categories.json'
          chmod 640 '${configPath}/categories.json'
          chown ${service.user}:${service.group} '${configPath}/categories.json'
        ''
      );
    };

    networking.hosts = mkIf (config.nixflix.nginx.enable && config.nixflix.nginx.addHostsEntries) {
      "127.0.0.1" = [ hostname ];
    };

    services.nginx.virtualHosts."${hostname}" = mkIf config.nixflix.nginx.enable {
      inherit (config.nixflix.nginx) forceSSL;
      useACMEHost = if config.nixflix.nginx.enableACME then config.nixflix.nginx.domain else null;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString service.webuiPort}";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_http_version 1.1;

          ${
            if config.nixflix.theme.enable then
              ''
                proxy_set_header Accept-Encoding "";
                proxy_hide_header "x-webkit-csp";
                proxy_hide_header "content-security-policy";
                proxy_hide_header "X-Frame-Options";

                sub_filter '</body>' '<link rel="stylesheet" type="text/css" href="https://theme-park.dev/css/base/qbittorrent/${config.nixflix.theme.name}.css"></body>';
                sub_filter_once on;
              ''
            else
              ""
          }
        '';
      };
    };
  };
}
