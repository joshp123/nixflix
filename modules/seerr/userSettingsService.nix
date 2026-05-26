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
  userSettings = cfg.settings.users;
  inherit (cfg) managedUsers;
in
{
  config = mkIf (nixflix.enable && cfg.enable) {
    systemd.services.seerr-user-settings = {
      description = "Configure Seerr default user settings";
      after = [ "seerr-setup.service" ];
      requires = [ "seerr-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script =
        let
          userSettingsJson = builtins.toJSON userSettings;
          managedUsersJson = pkgs.writeText "seerr-managed-users.json" (builtins.toJSON managedUsers);
        in
        ''
          set -euo pipefail

          BASE_URL="${baseUrl}"

          # Authenticate
          source ${authUtil.authScript}

          echo "Configuring default user settings..."

          # POST user settings (endpoint accepts partial documents)
          SETTINGS_RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST \
            ${authUtil.curlAuthArgs} \
            -H "Content-Type: application/json" \
            -d '${userSettingsJson}' \
            -w "\n%{http_code}" \
            "$BASE_URL/api/v1/settings/main")

          SETTINGS_HTTP_CODE=$(echo "$SETTINGS_RESPONSE" | ${pkgs.coreutils}/bin/tail -n1)
          if [ "$SETTINGS_HTTP_CODE" != "200" ] && [ "$SETTINGS_HTTP_CODE" != "201" ] && [ "$SETTINGS_HTTP_CODE" != "204" ]; then
            echo "Failed to configure user settings (HTTP $SETTINGS_HTTP_CODE)" >&2
            echo "$SETTINGS_RESPONSE" | ${pkgs.coreutils}/bin/head -n-1 >&2
            exit 1
          fi

          echo "User settings configured successfully"

          ${optionalString (managedUsers != { }) ''
            users_response="$(${pkgs.curl}/bin/curl -sS \
              --max-time 30 \
              ${authUtil.curlAuthArgs} \
              "$BASE_URL/api/v1/user?take=1000&skip=0")"

            ${pkgs.jq}/bin/jq -c 'to_entries[]' "${managedUsersJson}" | while read -r user_entry; do
              email="$(printf '%s' "$user_entry" | ${pkgs.jq}/bin/jq -r '.value.email')"
              permissions="$(printf '%s' "$user_entry" | ${pkgs.jq}/bin/jq -r '.value.permissions')"

              user_id="$(printf '%s' "$users_response" | ${pkgs.jq}/bin/jq -r --arg email "$email" '.results[] | select(.email == $email) | .id' | ${pkgs.coreutils}/bin/head -n1)"
              if [ -z "$user_id" ]; then
                echo "Seerr user not found: $email" >&2
                exit 1
              fi

              response="$(${pkgs.curl}/bin/curl -sS -X POST \
                --max-time 30 \
                ${authUtil.curlAuthArgs} \
                -H "Content-Type: application/json" \
                -d "$(${pkgs.jq}/bin/jq -nc --argjson permissions "$permissions" '{permissions: $permissions}')" \
                -w "\n%{http_code}" \
                "$BASE_URL/api/v1/user/$user_id/settings/permissions")"

              http_code="$(echo "$response" | ${pkgs.coreutils}/bin/tail -n1)"
              if [ "$http_code" != "200" ] && [ "$http_code" != "201" ] && [ "$http_code" != "204" ]; then
                echo "Failed to configure Seerr user permissions for $email (HTTP $http_code)" >&2
                echo "$response" | ${pkgs.gnused}/bin/sed '$d' >&2
                exit 1
              fi

              echo "Seerr user permissions configured: $email"
            done
          ''}
        '';
    };
  };
}
