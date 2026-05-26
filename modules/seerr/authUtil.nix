{
  lib,
  pkgs,
  cfg,
}:
let
  secrets = import ../../lib/secrets { inherit lib; };

  cookieFile = "/run/seerr/auth-cookie";
  apiKeyHeaderFile = "/run/seerr/api-key-header";

in
{
  inherit cookieFile;

  curlAuthArgs = ''--header @"${apiKeyHeaderFile}"'';

  authScript = pkgs.writeShellScript "seerr-auth" ''
    set -euo pipefail

    ${
      if cfg.apiKey != null then
        "SEERR_API_KEY=${secrets.toShellValue cfg.apiKey}"
      else
        ''
          SETTINGS_JSON="${cfg.dataDir}/settings.json"
          for _attempt in {1..60}; do
            if [ -s "$SETTINGS_JSON" ]; then
              SEERR_API_KEY="$(${pkgs.jq}/bin/jq -r '.main.apiKey // empty' "$SETTINGS_JSON")"
              if [ -n "$SEERR_API_KEY" ]; then
                break
              fi
            fi
            if [ "$_attempt" -eq 60 ]; then
              echo "Seerr API key is missing in $SETTINGS_JSON" >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/sleep 2
          done
        ''
    }
    printf 'X-Api-Key: %s' "$SEERR_API_KEY" > "${apiKeyHeaderFile}"
    ${pkgs.coreutils}/bin/chmod 600 "${apiKeyHeaderFile}"
  '';
}
