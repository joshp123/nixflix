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
    name = "prowlarr-indexers";
    description = "Configure Prowlarr indexers via API";
    after = [
      "prowlarr-config.service"
      "prowlarr-tags.service"
    ];
    requires = [
      "prowlarr-config.service"
      "prowlarr-tags.service"
    ];

    script = ''
      set -eu

      BASE_URL="http://127.0.0.1:${builtins.toString cfg.config.hostConfig.port}${cfg.config.hostConfig.urlBase}/api/${cfg.config.apiVersion}"

      is_placeholder_secret() {
        local value="$1"
        local normalized
        normalized=$(printf '%s' "$value" | ${pkgs.coreutils}/bin/tr '[:upper:]' '[:lower:]')

        case "$normalized" in
          ""|fake|dummy|example|test|testing|changeme|change-me|replace-me|placeholder|todo|tbd|api-key|apikey|secret|ptp-api-key|ptp-api-user|btn-api-key)
            return 0
            ;;
          *fake*|*dummy*|*placeholder*|*changeme*|*replace-me*|*ptp-api-key*|*ptp-api-user*|*btn-api-key*)
            return 0
            ;;
          *)
            return 1
            ;;
        esac
      }

      require_indexer_secret() {
        local indexer_name="$1"
        local field_name="$2"
        local value="$3"

        if is_placeholder_secret "$value"; then
          echo "Refusing to configure indexer $indexer_name: $field_name is empty or looks like a placeholder"
          echo "Private tracker APIs can ban invalid credentials; replace the secret with a real value first."
          exit 1
        fi
      }

      echo "Validating configured indexer secrets..."
      ${concatMapStringsSep "\n" (
        indexerConfig:
        let
          indexerName = indexerConfig.name;
          inherit (indexerConfig) apiKey username password;
          knownPrivateTrackerFields =
            if indexerName == "PassThePopcorn" then
              [
                "username"
                "apiKey"
              ]
            else if indexerName == "BroadcasTheNet" then
              [ "apiKey" ]
            else
              [ ];
        in
        ''
          INDEXER_API_KEY=${secrets.toShellValue (if apiKey == null then "" else apiKey)}
          INDEXER_USERNAME=${secrets.toShellValue (if username == null then "" else username)}
          INDEXER_PASSWORD=${secrets.toShellValue (if password == null then "" else password)}
          ${optionalString (apiKey != null || elem "apiKey" knownPrivateTrackerFields) ''
            require_indexer_secret ${escapeShellArg indexerName} "apiKey" "$INDEXER_API_KEY"
          ''}
          ${optionalString (username != null || elem "username" knownPrivateTrackerFields) ''
            require_indexer_secret ${escapeShellArg indexerName} "username" "$INDEXER_USERNAME"
          ''}
          ${optionalString (password != null) ''
            require_indexer_secret ${escapeShellArg indexerName} "password" "$INDEXER_PASSWORD"
          ''}
        ''
      ) cfg.config.indexers}

      echo "Fetching indexer schemas..."
      SCHEMAS=$(${
        mkSecureCurl cfg.config.apiKey {
          url = "$BASE_URL/indexer/schema";
          extraArgs = "-S";
        }
      })

      echo "Fetching existing indexers..."
      INDEXERS=$(${
        mkSecureCurl cfg.config.apiKey {
          url = "$BASE_URL/indexer";
          extraArgs = "-S";
        }
      })

      echo "Fetching tags..."
      ALL_TAGS=$(${
        mkSecureCurl cfg.config.apiKey {
          url = "$BASE_URL/tag";
          extraArgs = "-S";
        }
      })

      CONFIGURED_NAMES=$(cat <<'EOF'
      ${builtins.toJSON (map (i: i.name) cfg.config.indexers)}
      EOF
      )

      echo "Removing indexers not in configuration..."
      echo "$INDEXERS" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r indexer; do
        INDEXER_NAME=$(echo "$indexer" | ${pkgs.jq}/bin/jq -r '.name')
        INDEXER_ID=$(echo "$indexer" | ${pkgs.jq}/bin/jq -r '.id')

        if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$INDEXER_NAME" 'index($name)' >/dev/null 2>&1; then
          echo "Deleting indexer not in config: $INDEXER_NAME (ID: $INDEXER_ID)"
          ${
            mkSecureCurl cfg.config.apiKey {
              url = "$BASE_URL/indexer/$INDEXER_ID";
              method = "DELETE";
              extraArgs = "-Sf";
            }
          } >/dev/null
        fi
      done

      ${concatMapStringsSep "\n" (
        indexerConfig:
        let
          indexerName = indexerConfig.name;
          inherit (indexerConfig) apiKey username password;
          allOverrides = builtins.removeAttrs indexerConfig [
            "name"
            "apiKey"
            "username"
            "password"
            "tags"
          ];
          fieldOverrides = lib.filterAttrs (
            name: value: value != null && !lib.hasPrefix "_" name
          ) allOverrides;
          fieldOverridesJson = builtins.toJSON fieldOverrides;

          jqSecrets = secrets.mkJqSecretArgs {
            apiKey = if apiKey == null then "" else apiKey;
            username = if username == null then "" else username;
            password = if password == null then "" else password;
          };
          apiKeyFieldNames = builtins.toJSON [
            "apiKey"
            "aPIKey"
          ];
          usernameFieldNames = builtins.toJSON [
            "username"
            "aPIUser"
          ];
          passwordFieldNames = builtins.toJSON [ "password" ];
        in
        ''
          echo "Processing indexer: ${indexerName}"

          apply_field_overrides() {
            local indexer_json="$1"
            local overrides="$2"

            echo "$indexer_json" | ${pkgs.jq}/bin/jq \
              ${jqSecrets.flagsString} \
              --argjson apiKeyFieldNames ${escapeShellArg apiKeyFieldNames} \
              --argjson usernameFieldNames ${escapeShellArg usernameFieldNames} \
              --argjson passwordFieldNames ${escapeShellArg passwordFieldNames} \
              --argjson overrides "$overrides" '
                .fields[] |= (
                  . as $field |
                  if (($apiKeyFieldNames | index($field.name)) != null) and ${jqSecrets.refs.apiKey} != "" then .value = ${jqSecrets.refs.apiKey}
                  elif (($usernameFieldNames | index($field.name)) != null) and ${jqSecrets.refs.username} != "" then .value = ${jqSecrets.refs.username}
                  elif (($passwordFieldNames | index($field.name)) != null) and ${jqSecrets.refs.password} != "" then .value = ${jqSecrets.refs.password}
                  else .
                  end
                )
                | . + $overrides
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

          EXISTING_INDEXER=$(echo "$INDEXERS" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg indexerName} '.[] | select(.name == $name) | @json' || echo "")

          if [ -n "$EXISTING_INDEXER" ]; then
            echo "Indexer ${indexerName} already exists, updating..."
            INDEXER_ID=$(echo "$EXISTING_INDEXER" | ${pkgs.jq}/bin/jq -r '.id')

            UPDATED_INDEXER=$(apply_field_overrides "$EXISTING_INDEXER" "$FIELD_OVERRIDES")

            TAG_IDS=$(echo "$ALL_TAGS" | ${pkgs.jq}/bin/jq --argjson names ${escapeShellArg (builtins.toJSON indexerConfig.tags)} \
              '[.[] | select(.label as $l | $names | index($l)) | .id]')
            UPDATED_INDEXER=$(echo "$UPDATED_INDEXER" | ${pkgs.jq}/bin/jq --argjson tags "$TAG_IDS" '.tags = $tags')

            ${
              mkSecureCurl cfg.config.apiKey {
                url = "$BASE_URL/indexer/$INDEXER_ID";
                method = "PUT";
                headers = {
                  "Content-Type" = "application/json";
                };
                data = "$UPDATED_INDEXER";
                extraArgs = "-Sf";
              }
            } >/dev/null

            echo "Indexer ${indexerName} updated"
          else
            echo "Indexer ${indexerName} does not exist, creating..."

            SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg indexerName} '.[] | select(.name == $name) | @json' || echo "")

            if [ -z "$SCHEMA" ]; then
              echo "Error: No schema found for indexer ${indexerName}"
              exit 1
            fi

            NEW_INDEXER=$(apply_field_overrides "$SCHEMA" "$FIELD_OVERRIDES")

            TAG_IDS=$(echo "$ALL_TAGS" | ${pkgs.jq}/bin/jq --argjson names ${escapeShellArg (builtins.toJSON indexerConfig.tags)} \
              '[.[] | select(.label as $l | $names | index($l)) | .id]')
            NEW_INDEXER=$(echo "$NEW_INDEXER" | ${pkgs.jq}/bin/jq --argjson tags "$TAG_IDS" '.tags = $tags')

            ${
              mkSecureCurl cfg.config.apiKey {
                url = "$BASE_URL/indexer";
                method = "POST";
                headers = {
                  "Content-Type" = "application/json";
                };
                data = "$NEW_INDEXER";
                extraArgs = "-Sf";
              }
            } >/dev/null

            echo "Indexer ${indexerName} created"
          fi
        ''
      ) cfg.config.indexers}

      echo "Prowlarr indexers configuration complete"
    '';
  };
}
