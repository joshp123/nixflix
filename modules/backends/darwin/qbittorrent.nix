{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.torrentClients.qbittorrent;
  webui = cfg.serverConfig.Preferences.WebUI;
  stateDir = "${config.nixflix.stateDir}/qbittorrent";
  profileDir = cfg.profileDir or stateDir;
  configDir = "${profileDir}/qBittorrent/config";
  categoriesJson = builtins.toJSON (lib.mapAttrs (_name: path: { save_path = path; }) cfg.categories);
  categoriesFile = pkgs.writeText "categories.json" categoriesJson;

  inherit (builtins) concatStringsSep isAttrs isString;
  inherit (lib.generators) toINI mkKeyValueDefault mkValueStringDefault;
  gendeepINI = toINI {
    mkKeyValue =
      let
        sep = "=";
      in
      k: v:
      if isAttrs v then
        concatStringsSep "\n" (
          collect isString (
            mapAttrsRecursive (
              path: value:
              "${escape [ sep ] (concatStringsSep "\\" ([ k ] ++ path))}${sep}${
                replaceString "\n" "\\n" (mkValueStringDefault { } value)
              }"
            ) v
          )
        )
      else
        mkKeyValueDefault { } sep k v;
  };
  configFile = pkgs.writeText "qBittorrent.ini" (gendeepINI cfg.serverConfig);
  mkLaunchdService = import ./mk-launchd-service.nix { inherit lib; };
in
{
  imports = [ ../../torrentClients/qbittorrent.nix ];

  config = mkIf config.nixflix.enable (mkMerge [
    {
      nixflix.torrentClients.qbittorrent = {
        user = mkOverride 900 "_nixflix";
        group = mkOverride 900 "_nixflix";
        serverConfig.Preferences.WebUI.Address = mkDefault "*";
      };
    }
    (mkIf cfg.enable {
      assertions = [
        {
          assertion = !config.nixflix.nginx.enable;
          message = "nixflix.nginx is not implemented for qBittorrent on Darwin yet.";
        }
        {
          assertion = cfg.user != "root" && cfg.group != "wheel";
          message = "nixflix.torrentClients.qbittorrent must not run as root:wheel on Darwin.";
        }
        {
          assertion = webui.Address == "127.0.0.1" || webui.Address == "localhost" || webui ? Password_PBKDF2;
          message = "nixflix.torrentClients.qbittorrent.serverConfig.Preferences.WebUI.Password_PBKDF2 must be set when qBittorrent binds beyond localhost on Darwin.";
        }
      ];

      system.activationScripts.users.text = mkAfter ''
        mkdir -p '${stateDir}' '${profileDir}' '${configDir}' '${cfg.downloadsDir}' '${cfg.serverConfig.BitTorrent.Session.DefaultSavePath}'
        ${concatMapStringsSep "\n" (path: "mkdir -p '${path}'") (
          attrValues (filterAttrs (_name: path: path != "") cfg.categories)
        )}
        restart_qbittorrent=0
        if [ -f '${configDir}/qBittorrent.ini' ] && ! cmp -s '${configFile}' '${configDir}/qBittorrent.ini'; then
          if /bin/launchctl print system/org.nixflix.qbittorrent >/dev/null 2>&1; then
            restart_qbittorrent=1
            /bin/launchctl bootout system/org.nixflix.qbittorrent >/dev/null 2>&1 || true
          fi
        fi
        install -m 600 '${configFile}' '${configDir}/qBittorrent.ini'
        install -m 640 '${categoriesFile}' '${configDir}/categories.json'
        chown -R '${cfg.user}:${cfg.group}' '${stateDir}' '${profileDir}' '${cfg.downloadsDir}' '${cfg.serverConfig.BitTorrent.Session.DefaultSavePath}'
        ${concatMapStringsSep "\n" (path: "chown '${cfg.user}:${cfg.group}' '${path}'") (
          attrValues (filterAttrs (_name: path: path != "") cfg.categories)
        )}
        if [ "$restart_qbittorrent" -eq 1 ] && [ -f /Library/LaunchDaemons/org.nixflix.qbittorrent.plist ]; then
          /bin/launchctl bootstrap system /Library/LaunchDaemons/org.nixflix.qbittorrent.plist >/dev/null 2>&1 || true
          /bin/launchctl enable system/org.nixflix.qbittorrent >/dev/null 2>&1 || true
          /bin/launchctl kickstart -k system/org.nixflix.qbittorrent >/dev/null 2>&1 || true
        fi
      '';

      launchd.daemons.qbittorrent = mkLaunchdService {
        name = "qbittorrent";
        label = "org.nixflix.qbittorrent";
        serviceConfig = {
          ProgramArguments = [
            "${getExe (cfg.package or pkgs.qbittorrent-nox)}"
            "--profile=${profileDir}"
          ]
          ++ optionals (cfg.webuiPort != null) [ "--webui-port=${toString cfg.webuiPort}" ]
          ++ optionals ((cfg.torrentingPort or null) != null) [
            "--torrenting-port=${toString cfg.torrentingPort}"
          ]
          ++ (cfg.extraArgs or [ ]);
          WorkingDirectory = profileDir;
          UserName = cfg.user;
          GroupName = cfg.group;
          StandardOutPath = "${stateDir}/stdout.log";
          StandardErrorPath = "${stateDir}/stderr.log";
          EnvironmentVariables = {
            HOME = profileDir;
            PATH = "${
              lib.makeBinPath [
                pkgs.coreutils
                pkgs.qbittorrent-nox
              ]
            }:/usr/bin:/bin:/usr/sbin:/sbin";
          };
        };
      };
    })
  ]);
}
