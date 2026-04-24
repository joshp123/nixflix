{
  lib,
  pkgs,
  cfg,
}:
let
  secrets = import ../../lib/secrets { inherit lib; };

  tokenFile = "${cfg.dataDir}/auth-token";
  token = {
    _secret = tokenFile;
  };
in
{
  inherit token;

  authScript = pkgs.writeShellScript "jellyfin-auth" ''
    set -eu

    API_KEY=${secrets.toShellValue cfg.apiKey}
    printf 'MediaBrowser Client="nixflix", Device="nixflix", DeviceId="nixflix-auth", Version="1.0.0", Token="%s"' "$API_KEY" > "${tokenFile}"
    chmod 600 "${tokenFile}"
  '';
}
