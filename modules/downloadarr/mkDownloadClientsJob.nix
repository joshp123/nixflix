{
  config,
  lib,
  pkgs,
  ...
}:
serviceName:
with lib;
let
  secrets = import ../../lib/secrets { inherit lib; };
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  cfg = config.nixflix.downloadarr;

  allClients = filter (c: c.enable) (
    builtins.attrValues (
      builtins.removeAttrs cfg [
        "extraClients"
        "enable"
      ]
    )
    ++ cfg.extraClients
  );

  clientDependencies = unique (concatMap (c: c.dependencies) allClients);

  categoryFieldFor =
    name:
    {
      radarr = "movieCategory";
      sonarr = "tvCategory";
      sonarr-anime = "tvCategory";
      lidarr = "musicCategory";
      prowlarr = "category";
    }
    .${name};

  transformClient =
    name: client:
    let
      stripped = builtins.removeAttrs client [
        "categories"
        "dependencies"
      ];
      categoryField = categoryFieldFor name;
      categoryValue = client.categories.${name};
    in
    stripped // { ${categoryField} = categoryValue; };

  serviceConfig = config.nixflix.${serviceName}.config;
  capitalizedName =
    toUpper (builtins.substring 0 1 serviceName) + builtins.substring 1 (-1) serviceName;
  clients = map (transformClient serviceName) allClients;
in
{
  mkJob = {
    name = "${serviceName}-downloadclients";
    description = "Configure ${serviceName} download clients via API";
    after = [
      "${serviceName}.service"
      "${serviceName}-config.service"
    ]
    ++ clientDependencies;
    requires = [
      "${serviceName}.service"
      "${serviceName}-config.service"
    ]
    ++ clientDependencies;
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStartPre =
      "${pkgs.curl}/bin/curl --retry 30 --retry-delay 2 --retry-connrefused -so /dev/null"
      + " http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}/system/status";
    script = ''
      set -eu

      BASE_URL="http://127.0.0.1:${builtins.toString serviceConfig.hostConfig.port}${serviceConfig.hostConfig.urlBase}/api/${serviceConfig.apiVersion}"

      echo "Fetching download client schemas..."
      SCHEMAS=$(${
        mkSecureCurl serviceConfig.apiKey {
          url = "$BASE_URL/downloadclient/schema";
          extraArgs = "-S";
        }
      })

      echo "Fetching existing download clients..."
      DOWNLOAD_CLIENTS=$(${
        mkSecureCurl serviceConfig.apiKey {
          url = "$BASE_URL/downloadclient";
          extraArgs = "-S";
        }
      })

      CONFIGURED_NAMES=$(cat <<'EOF'
      ${builtins.toJSON (map (d: d.name) clients)}
      EOF
      )

      echo "Removing download clients not in configuration..."
      echo "$DOWNLOAD_CLIENTS" | ${pkgs.jq}/bin/jq -r '.[] | @json' | while IFS= read -r downloadClient; do
        CLIENT_NAME=$(echo "$downloadClient" | ${pkgs.jq}/bin/jq -r '.name')
        CLIENT_ID=$(echo "$downloadClient" | ${pkgs.jq}/bin/jq -r '.id')

        if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$CLIENT_NAME" 'index($name)' >/dev/null 2>&1; then
          echo "Deleting download client not in config: $CLIENT_NAME (ID: $CLIENT_ID)"
          ${
            mkSecureCurl serviceConfig.apiKey {
              url = "$BASE_URL/downloadclient/$CLIENT_ID";
              method = "DELETE";
              extraArgs = "-Sf";
            }
          } >/dev/null
        fi
      done

      ${concatMapStringsSep "\n" (
        clientConfig:
        let
          clientName = clientConfig.name;
          inherit (clientConfig) implementationName;
          apiKey = clientConfig.apiKey or null;
          username = clientConfig.username or null;
          password = clientConfig.password or null;
          allOverrides = builtins.removeAttrs clientConfig [
            "implementationName"
            "apiKey"
            "username"
            "password"
          ];
          fieldOverrides = filterAttrs (name: value: value != null && !hasPrefix "_" name) allOverrides;
          fieldOverridesJson = builtins.toJSON fieldOverrides;

          jqSecrets = secrets.mkJqSecretArgs {
            apiKey = if apiKey == null then "" else apiKey;
            username = if username == null then "" else username;
            password = if password == null then "" else password;
          };
        in
        ''
          echo "Processing download client: ${clientName}"

          apply_field_overrides() {
            local client_json="$1"
            local overrides="$2"

            echo "$client_json" | ${pkgs.jq}/bin/jq \
              ${jqSecrets.flagsString} \
              --argjson overrides "$overrides" '
                .fields[] |= (
                  if .name == "apiKey" and ${jqSecrets.refs.apiKey} != "" then .value = ${jqSecrets.refs.apiKey}
                  elif .name == "username" and ${jqSecrets.refs.username} != "" then .value = ${jqSecrets.refs.username}
                  elif .name == "password" and ${jqSecrets.refs.password} != "" then .value = ${jqSecrets.refs.password}
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

          EXISTING_CLIENT=$(echo "$DOWNLOAD_CLIENTS" | ${pkgs.jq}/bin/jq -r --arg name ${escapeShellArg clientName} '.[] | select(.name == $name) | @json' || echo "")

          if [ -n "$EXISTING_CLIENT" ]; then
            echo "Download client ${clientName} already exists, updating..."
            CLIENT_ID=$(echo "$EXISTING_CLIENT" | ${pkgs.jq}/bin/jq -r '.id')

            UPDATED_CLIENT=$(apply_field_overrides "$EXISTING_CLIENT" "$FIELD_OVERRIDES")

            for _retry_attempt in $(seq 1 5); do
              if ${
                mkSecureCurl serviceConfig.apiKey {
                  url = "$BASE_URL/downloadclient/$CLIENT_ID";
                  method = "PUT";
                  headers = {
                    "Content-Type" = "application/json";
                  };
                  data = "$UPDATED_CLIENT";
                  extraArgs = "-Sf";
                }
              } >/dev/null; then
                break
              fi
              if [ "$_retry_attempt" -eq 5 ]; then
                echo "Error: Failed to update download client ${clientName} after 5 attempts"
                exit 1
              fi
              echo "Attempt $_retry_attempt to update ${clientName} failed, retrying in 1 second..."
              sleep 1
            done

            echo "Download client ${clientName} updated"
          else
            echo "Download client ${clientName} does not exist, creating..."

            SCHEMA=$(echo "$SCHEMAS" | ${pkgs.jq}/bin/jq -r --arg implName ${escapeShellArg implementationName} '.[] | select(.implementationName == $implName) | @json' || echo "")

            if [ -z "$SCHEMA" ]; then
              echo "Error: No schema found for download client implementationName ${implementationName}"
              exit 1
            fi

            NEW_CLIENT=$(apply_field_overrides "$SCHEMA" "$FIELD_OVERRIDES")

            for _retry_attempt in $(seq 1 5); do
              if ${
                mkSecureCurl serviceConfig.apiKey {
                  url = "$BASE_URL/downloadclient";
                  method = "POST";
                  headers = {
                    "Content-Type" = "application/json";
                  };
                  data = "$NEW_CLIENT";
                  extraArgs = "-Sf";
                }
              } >/dev/null; then
                break
              fi
              if [ "$_retry_attempt" -eq 5 ]; then
                echo "Error: Failed to create download client ${clientName} after 5 attempts"
                exit 1
              fi
              echo "Attempt $_retry_attempt to create ${clientName} failed, retrying in 1 second..."
              sleep 1
            done

            echo "Download client ${clientName} created"
          fi
        ''
      ) clients}

      echo "${capitalizedName} download clients configuration complete"
    '';
  };
}
