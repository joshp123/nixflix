{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.nixflix.prowlarr;
  secrets = import ../../lib/secrets { inherit lib; };
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
in
{
  mkJob = {
    name = "prowlarr-applications";
    description = "Configure Prowlarr applications via API";
    after = [
      "prowlarr-config.service"
    ]
    ++ lib.optional config.nixflix.radarr.enable "radarr-config.service"
    ++ lib.optional config.nixflix.sonarr.enable "sonarr-config.service"
    ++ lib.optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service"
    ++ lib.optional (config.nixflix.lidarr.enable or false) "lidarr-config.service";
    requires = [
      "prowlarr-config.service"
    ]
    ++ lib.optional config.nixflix.radarr.enable "radarr-config.service"
    ++ lib.optional config.nixflix.sonarr.enable "sonarr-config.service"
    ++ lib.optional config.nixflix.sonarr-anime.enable "sonarr-anime-config.service"
    ++ lib.optional (config.nixflix.lidarr.enable or false) "lidarr-config.service";
    script = ''
      set -eu

      BASE_URL="http://127.0.0.1:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}"

      echo "Fetching application schemas..."
      SCHEMAS=$(${
        mkSecureCurl cfg.config.apiKey {
          url = "$BASE_URL/applications/schema";
          extraArgs = "-S";
        }
      })

      echo "Fetching existing applications..."
      APPLICATIONS=$(${
        mkSecureCurl cfg.config.apiKey {
          url = "$BASE_URL/applications";
          extraArgs = "-S";
        }
      })

      CONFIGURED_NAMES=$(cat <<'EOF'
      ${builtins.toJSON (map (a: a.name) cfg.config.applications)}
      EOF
      )

      echo "Removing applications not in configuration..."
      echo "$APPLICATIONS" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r application; do
        APPLICATION_NAME=$(echo "$application" | ${pkgs.jq}/bin/jq -r '.name')
        APPLICATION_ID=$(echo "$application" | ${pkgs.jq}/bin/jq -r '.id')

        if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$APPLICATION_NAME" 'index($name)' >/dev/null; then
          echo "Deleting application not in config: $APPLICATION_NAME (ID: $APPLICATION_ID)"
          ${
            mkSecureCurl cfg.config.apiKey {
              url = "$BASE_URL/applications/$APPLICATION_ID";
              method = "DELETE";
              extraArgs = "-Sf";
            }
          } >/dev/null
        fi
      done

      ${concatMapStringsSep "\n" (
        applicationConfig:
        let
          applicationName = applicationConfig.name;
          inherit (applicationConfig) implementationName;
          inherit (applicationConfig) apiKey;
          allOverrides = builtins.removeAttrs applicationConfig [
            "implementationName"
            "apiKey"
          ];
          fieldOverrides = lib.filterAttrs (
            name: value: value != null && !lib.hasPrefix "_" name
          ) allOverrides;
          fieldOverridesJson = builtins.toJSON fieldOverrides;

          jqSecrets = secrets.mkJqSecretArgs { inherit apiKey; };
        in
        ''
          echo "Processing application: ${applicationName}"

          apply_field_overrides() {
            local application_json="$1"
            local overrides="$2"

            echo "$application_json" | ${pkgs.jq}/bin/jq \
              ${jqSecrets.flagsString} \
              --argjson overrides "$overrides" '
                .fields[] |= (if .name == "apiKey" then .value = ${jqSecrets.refs.apiKey} else . end)
                | .name = $overrides.name
                | .fields[] |= (
                    . as $field |
                    if $overrides[$field.name] != null then
                      .value = $overrides[$field.name]
                    else
                      .
                    end
                  )
              '
          }

          FIELD_OVERRIDES=${escapeShellArg fieldOverridesJson}

          EXISTING_APPLICATION=$(echo "$APPLICATIONS" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg applicationName} '.[] | select(.name == $name) | @json' || echo "")

          if [ -n "$EXISTING_APPLICATION" ]; then
            echo "Application ${applicationName} already exists, updating..."
            APPLICATION_ID=$(echo "$EXISTING_APPLICATION" | ${pkgs.jq}/bin/jq -r '.id')

            UPDATED_APPLICATION=$(apply_field_overrides "$EXISTING_APPLICATION" "$FIELD_OVERRIDES")

            RESPONSE_FILE=$(mktemp)
            set +e
            ${
              mkSecureCurl cfg.config.apiKey {
                url = "$BASE_URL/applications/$APPLICATION_ID";
                method = "PUT";
                headers = {
                  "Content-Type" = "application/json";
                };
                data = "$UPDATED_APPLICATION";
                extraArgs = "-S --fail-with-body";
              }
            } > "$RESPONSE_FILE" 2>&1
            CURL_EXIT=$?
            set -e
            if [ "$CURL_EXIT" -ne 0 ]; then
              echo "Error: Updating application ${applicationName} failed (curl exit code: $CURL_EXIT)"
              echo "Request body (secrets redacted):"
              echo "$UPDATED_APPLICATION" | ${pkgs.jq}/bin/jq '(.fields[]? | select(.name == "apiKey") | .value) = "***"' 2>/dev/null || echo "$UPDATED_APPLICATION"
              echo "Response:"
              cat "$RESPONSE_FILE"
              rm -f "$RESPONSE_FILE"
              exit 1
            fi
            rm -f "$RESPONSE_FILE"

            echo "Application ${applicationName} updated"
          else
            echo "Application ${applicationName} does not exist, creating..."

            SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r --arg implName ${escapeShellArg implementationName} '.[] | select(.implementationName == $implName) | @json' || echo "")

            if [ -z "$SCHEMA" ]; then
              echo "Error: No schema found for application implementationName ${implementationName}"
              exit 1
            fi

            NEW_APPLICATION=$(apply_field_overrides "$SCHEMA" "$FIELD_OVERRIDES")

            RESPONSE_FILE=$(mktemp)
            set +e
            ${
              mkSecureCurl cfg.config.apiKey {
                url = "$BASE_URL/applications";
                method = "POST";
                headers = {
                  "Content-Type" = "application/json";
                };
                data = "$NEW_APPLICATION";
                extraArgs = "-S --fail-with-body";
              }
            } > "$RESPONSE_FILE" 2>&1
            CURL_EXIT=$?
            set -e
            if [ "$CURL_EXIT" -ne 0 ]; then
              echo "Error: Creating application ${applicationName} failed (curl exit code: $CURL_EXIT)"
              echo "Request body (secrets redacted):"
              echo "$NEW_APPLICATION" | ${pkgs.jq}/bin/jq '(.fields[]? | select(.name == "apiKey") | .value) = "***"' 2>/dev/null || echo "$NEW_APPLICATION"
              echo "Response:"
              cat "$RESPONSE_FILE"
              rm -f "$RESPONSE_FILE"
              exit 1
            fi
            rm -f "$RESPONSE_FILE"

            echo "Application ${applicationName} created"
          fi
        ''
      ) cfg.config.applications}

      echo "Prowlarr applications configuration complete"
    '';
  };
}
