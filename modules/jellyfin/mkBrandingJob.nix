{
  cfg,
  lib,
  pkgs,
}:
with lib;
let
  util = import ./util.nix { inherit lib; };
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  authUtil = import ./authUtil.nix { inherit lib pkgs cfg; };

  brandingConfig = util.recursiveTransform (removeAttrs cfg.branding [ "splashscreenLocation" ]);
  brandingConfigJson = builtins.toJSON brandingConfig;
  brandingConfigFile = pkgs.writeText "jellyfin-branding-config.json" brandingConfigJson;

  baseUrl =
    if cfg.network.baseUrl == "" then
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}"
    else
      "http://127.0.0.1:${toString cfg.network.internalHttpPort}/${cfg.network.baseUrl}";

  waitForApiScript = import ./waitForApiScript.nix {
    inherit pkgs;
    jellyfinCfg = cfg;
  };
in
{
  description = "Configure Jellyfin Branding via API";
  after = [ "jellyfin-setup-wizard.service" ];
  requires = [ "jellyfin-setup-wizard.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig.ExecStartPre = waitForApiScript;

  script = ''
    set -eu

    BASE_URL="${baseUrl}"

    echo "Configuring Jellyfin branding settings..."

    source ${authUtil.authScript}

    RESPONSE=$(${
      mkSecureCurl authUtil.token {
        method = "POST";
        url = "$BASE_URL/System/Configuration/Branding";
        apiKeyHeader = "Authorization";
        headers = {
          "Content-Type" = "application/json";
        };
        data = "@${brandingConfigFile}";
        extraArgs = "-w \"\\n%{http_code}\"";
      }
    })

    HTTP_CODE=$(echo "$RESPONSE" | ${pkgs.coreutils}/bin/tail -n1)
    BODY=$(echo "$RESPONSE" | ${pkgs.gnused}/bin/sed '$d')

    echo "Branding config response (HTTP $HTTP_CODE): $BODY"

    if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
      echo "Failed to configure Jellyfin branding settings (HTTP $HTTP_CODE)" >&2
      exit 1
    fi

    ${optionalString (cfg.branding.splashscreenEnabled && cfg.branding.splashscreenLocation != "") ''
      echo "Uploading custom splashscreen image..."

      SPLASHSCREEN_FILE="${cfg.branding.splashscreenLocation}"

      if [ ! -f "$SPLASHSCREEN_FILE" ]; then
        echo "Error: Splashscreen file not found at $SPLASHSCREEN_FILE" >&2
        exit 1
      fi

      case "''${SPLASHSCREEN_FILE##*.}" in
        png) CONTENT_TYPE="image/png" ;;
        jpg|jpeg) CONTENT_TYPE="image/jpeg" ;;
        webp) CONTENT_TYPE="image/webp" ;;
        *)
          echo "Error: Unsupported splashscreen image format. Supported: png, jpg, jpeg, webp" >&2
          exit 1
          ;;
      esac

      BASE64_IMAGE=$(${pkgs.coreutils}/bin/base64 -w 0 "$SPLASHSCREEN_FILE")

      SPLASH_RESPONSE=$(${
        mkSecureCurl authUtil.token {
          method = "POST";
          url = "$BASE_URL/Branding/Splashscreen";
          apiKeyHeader = "Authorization";
          headers = {
            "Content-Type" = "$CONTENT_TYPE";
          };
          data = "$BASE64_IMAGE";
          extraArgs = "-w \"\\n%{http_code}\"";
        }
      })

      SPLASH_HTTP_CODE=$(echo "$SPLASH_RESPONSE" | ${pkgs.coreutils}/bin/tail -n1)
      SPLASH_BODY=$(echo "$SPLASH_RESPONSE" | ${pkgs.gnused}/bin/sed '$d')

      echo "Splashscreen upload response (HTTP $SPLASH_HTTP_CODE): $SPLASH_BODY"

      if [ "$SPLASH_HTTP_CODE" -eq 204 ]; then
        echo "Custom splashscreen uploaded successfully"
      elif [ "$SPLASH_HTTP_CODE" -eq 400 ]; then
        echo "Failed to upload splashscreen: Invalid content type or image data (HTTP $SPLASH_HTTP_CODE)" >&2
        exit 1
      elif [ "$SPLASH_HTTP_CODE" -eq 403 ]; then
        echo "Failed to upload splashscreen: Insufficient permissions (HTTP $SPLASH_HTTP_CODE)" >&2
        exit 1
      else
        echo "Failed to upload splashscreen (HTTP $SPLASH_HTTP_CODE)" >&2
        exit 1
      fi
    ''}

    echo "Jellyfin branding configuration completed successfully"
  '';
}
