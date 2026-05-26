{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  inherit (config) nixflix;
  cfg = nixflix.seerr;
  authUtil = import ./authUtil.nix {
    inherit
      lib
      pkgs
      cfg
      ;
  };
  baseUrl = "http://127.0.0.1:${toString cfg.port}";
  libraryNamesFile = pkgs.writeText "seerr-plex-library-names.json" (
    builtins.toJSON cfg.plex.libraryNames
  );
in
{
  config = mkIf (nixflix.enable && cfg.enable && cfg.plex.enable) {
    systemd.services.seerr-setup = {
      description = "Complete Seerr initial setup with Plex";
      after = [ "seerr.service" ];
      requires = [ "seerr.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        BASE_URL="${baseUrl}"

        echo "Waiting for Seerr..."
        for _attempt in {1..60}; do
          if ${pkgs.curl}/bin/curl --retry 0 --connect-timeout 2 --max-time 5 -fsS -o /dev/null "$BASE_URL/api/v1/status"; then
            break
          fi
          if [ "$_attempt" -eq 60 ]; then
            echo "Timed out waiting for Seerr at $BASE_URL" >&2
            exit 1
          fi
            ${pkgs.coreutils}/bin/sleep 2
        done

        settings_json="${cfg.dataDir}/settings.json"
        seerr_db="${cfg.dataDir}/db/db.sqlite3"

        if [ ! -s "$settings_json" ] || [ ! -s "$seerr_db" ]; then
          echo "Seerr Plex setup requires restored settings.json and db/db.sqlite3 state" >&2
          exit 1
        fi

        if ! ${pkgs.jq}/bin/jq -e '.main.mediaServerType == 1' "$settings_json" >/dev/null; then
          echo "Seerr restored settings are not Plex-backed; refusing Plex setup" >&2
          exit 1
        fi

        admin_plex_token_count="$(
          ${pkgs.sqlite}/bin/sqlite3 \
            "$seerr_db" \
            "select count(*) from user where id = 1 and plexToken is not null and length(plexToken) > 0;" \
            2>/dev/null || echo 0
        )"
        if [ "$admin_plex_token_count" -lt 1 ]; then
          echo "Seerr Plex setup requires a restored admin Plex token" >&2
          exit 1
        fi

        source ${authUtil.authScript}

        plex_payload="$(${pkgs.jq}/bin/jq -n \
          --arg ip "${cfg.plex.hostname}" \
          --arg port "${toString cfg.plex.port}" \
          --arg useSsl "${boolToString cfg.plex.useSsl}" \
          --arg webAppUrl "${cfg.plex.webAppUrl}" \
          '{
            ip: $ip,
            port: ($port | tonumber),
            useSsl: ($useSsl == "true"),
            webAppUrl: $webAppUrl
          }')"

        echo "Configuring Seerr Plex endpoint: ${cfg.plex.hostname}:${toString cfg.plex.port}"
        plex_response="$(${pkgs.curl}/bin/curl -sS -X POST \
          --max-time 30 \
          ${authUtil.curlAuthArgs} \
          -H "Content-Type: application/json" \
          -d "$plex_payload" \
          -w "\n%{http_code}" \
          "$BASE_URL/api/v1/settings/plex")"
        plex_http_code="$(echo "$plex_response" | ${pkgs.coreutils}/bin/tail -n1)"
        if [ "$plex_http_code" != "200" ]; then
          echo "Failed to configure Seerr Plex endpoint (HTTP $plex_http_code)" >&2
          echo "$plex_response" | ${pkgs.gnused}/bin/sed '$d' >&2
          exit 1
        fi

        libraries="$(${pkgs.curl}/bin/curl -fsS \
          --max-time 30 \
          ${authUtil.curlAuthArgs} \
          "$BASE_URL/api/v1/settings/plex/library?sync=true")"

        ${
          if cfg.plex.enableAllLibraries then
            ''
              library_ids="$(echo "$libraries" | ${pkgs.jq}/bin/jq -r '.[].id' | ${pkgs.coreutils}/bin/paste -sd, -)"
            ''
          else
            ''
              library_ids="$(echo "$libraries" | ${pkgs.jq}/bin/jq -r \
                --slurpfile names "${libraryNamesFile}" \
                '.[] | select(.name as $name | $names[0] | index($name)) | .id' | ${pkgs.coreutils}/bin/paste -sd, -)"
            ''
        }

        if [ -z "$library_ids" ]; then
          echo "No Plex libraries matched Seerr configuration" >&2
          echo "$libraries" | ${pkgs.jq}/bin/jq -r '.[] | "  - \(.name) (\(.type))"' >&2
          exit 1
        fi

        echo "Enabling Seerr Plex libraries: $library_ids"
        ${pkgs.curl}/bin/curl -fsS \
          --max-time 30 \
          ${authUtil.curlAuthArgs} \
          "$BASE_URL/api/v1/settings/plex/library?enable=$library_ids" >/dev/null

        ${pkgs.curl}/bin/curl -fsS -X POST \
          --max-time 30 \
          ${authUtil.curlAuthArgs} \
          -H "Content-Type: application/json" \
          -d '{"start":true}' \
          "$BASE_URL/api/v1/settings/plex/sync" >/dev/null

        init_response="$(${pkgs.curl}/bin/curl -sS -X POST \
          --max-time 30 \
          ${authUtil.curlAuthArgs} \
          -H "Content-Type: application/json" \
          -w "\n%{http_code}" \
          "$BASE_URL/api/v1/settings/initialize")"
        init_http_code="$(echo "$init_response" | ${pkgs.coreutils}/bin/tail -n1)"
        case "$init_http_code" in
          200 | 201 | 204 | 409) ;;
          *)
            echo "Failed to initialize Seerr settings (HTTP $init_http_code)" >&2
            echo "$init_response" | ${pkgs.gnused}/bin/sed '$d' >&2
            exit 1
            ;;
        esac

        echo "Seerr Plex configuration completed"
      '';
    };
  };
}
