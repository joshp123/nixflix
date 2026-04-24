{
  config,
  cfg,
  lib,
  pkgs,
}:
with lib;
let
  util = import ./util.nix { inherit lib; };
  mkSecureCurl = import ../../lib/mk-secure-curl.nix { inherit lib pkgs; };
  authUtil = import ./authUtil.nix { inherit lib pkgs cfg; };

  pathsToPathInfos = paths: map (path: { Path = path; }) paths;

  buildLibraryOptions =
    _libraryName: libraryCfg:
    let
      cleanedConfig = removeAttrs libraryCfg [
        "collectionType"
        "paths"
      ];
      withPathInfos = cleanedConfig // {
        pathInfos = pathsToPathInfos libraryCfg.paths;
      };
    in
    util.recursiveTransform withPathInfos;

  buildCreatePayload = libraryName: libraryCfg: {
    LibraryOptions = buildLibraryOptions libraryName libraryCfg;
  };

  libraryConfigFiles = mapAttrs (
    libraryName: libraryCfg:
    pkgs.writeText "jellyfin-library-${libraryName}.json" (
      builtins.toJSON (buildCreatePayload libraryName libraryCfg)
    )
  ) cfg.libraries;

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
  description = "Configure Jellyfin Libraries via API";
  after = [ "jellyfin-setup-wizard.service" ] ++ config.nixflix.serviceDependencies;
  requires = [ "jellyfin-setup-wizard.service" ] ++ config.nixflix.serviceDependencies;
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    TimeoutStartSec = 300;
    ExecStartPre = waitForApiScript;
  };

  script = ''
    set -eu

    BASE_URL="${baseUrl}"

    http_status() {
      echo "$1" | tail -n1
    }

    http_body() {
      echo "$1" | sed '$d'
    }

    require_http_success() {
      local http_code="$1"
      local action="$2"

      if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
        echo "Failed to $action (HTTP $http_code)" >&2
        exit 1
      fi
    }

    warn_http_failure() {
      local http_code="$1"
      local action="$2"

      if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
        echo "Warning: Failed to $action (HTTP $http_code)" >&2
        return 1
      fi
    }

    echo "Configuring Jellyfin libraries..."

    echo "Creating library paths..."
    ${concatStringsSep "\n" (
      mapAttrsToList (
        _libraryName: libraryCfg:
        concatMapStringsSep "\n" (path: ''
          mkdir -p "${path}"
          echo "Created path: ${path}"
        '') libraryCfg.paths
      ) cfg.libraries
    )}

    source ${authUtil.authScript}

    echo "Fetching existing libraries from $BASE_URL/Library/VirtualFolders..."
    LIBRARIES_RESPONSE=$(${
      mkSecureCurl authUtil.token {
        url = "$BASE_URL/Library/VirtualFolders";
        apiKeyHeader = "Authorization";
        extraArgs = "-w \"\\n%{http_code}\"";
      }
    })

    LIBRARIES_HTTP_CODE=$(http_status "$LIBRARIES_RESPONSE")
    LIBRARIES_JSON=$(http_body "$LIBRARIES_RESPONSE")

    echo "Libraries endpoint response (HTTP $LIBRARIES_HTTP_CODE)"
    require_http_success "$LIBRARIES_HTTP_CODE" "fetch libraries from Jellyfin API"

    CONFIGURED_NAMES=$(cat <<'EOF'
    ${builtins.toJSON (attrNames cfg.libraries)}
    EOF
    )

    STATE_FILE="${cfg.dataDir}/nixflix-managed-libraries.json"

    if [ -f "$STATE_FILE" ]; then
      PREVIOUS_MANAGED=$(cat "$STATE_FILE")
    else
      PREVIOUS_MANAGED="[]"
    fi

    echo "Checking for removed libraries to delete..."
    EXISTING_NAMES=$(echo "$LIBRARIES_JSON" | ${pkgs.jq}/bin/jq -c '[.[].Name]')

    echo "$PREVIOUS_MANAGED" | ${pkgs.jq}/bin/jq -r '.[]' | while IFS= read -r lib_name; do
      if ! echo "$CONFIGURED_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$lib_name" 'index($name)' >/dev/null 2>&1; then
        if echo "$EXISTING_NAMES" | ${pkgs.jq}/bin/jq -e --arg name "$lib_name" 'index($name)' >/dev/null 2>&1; then
          echo "Deleting removed library: $lib_name"
          DELETE_RESPONSE=$(${
            mkSecureCurl authUtil.token {
              method = "DELETE";
              url = "$BASE_URL/Library/VirtualFolders?name=$(${pkgs.jq}/bin/jq -rn --arg n \"$lib_name\" '\$n|@uri')";
              apiKeyHeader = "Authorization";
              extraArgs = "-w \"\\n%{http_code}\"";
            }
          })

          DELETE_HTTP_CODE=$(http_status "$DELETE_RESPONSE")

          if warn_http_failure "$DELETE_HTTP_CODE" "delete library $lib_name"; then
            echo "Successfully deleted library: $lib_name"
          fi
        fi
      fi
    done

    echo "Refreshing library list..."
    LIBRARIES_JSON=$(${
      mkSecureCurl authUtil.token {
        url = "$BASE_URL/Library/VirtualFolders";
        apiKeyHeader = "Authorization";
      }
    })

    ${concatStringsSep "\n" (
      mapAttrsToList (libraryName: libraryCfg: ''
            echo "Processing library: ${libraryName}"

            EXISTING_LIBRARY=$(echo "$LIBRARIES_JSON" | ${pkgs.jq}/bin/jq -r --arg name "${libraryName}" '.[] | select(.Name == $name) // empty')

            if [ -z "$EXISTING_LIBRARY" ]; then
              echo "Creating new library: ${libraryName}"

              CREATE_RESPONSE=$(${
                mkSecureCurl authUtil.token {
                  method = "POST";
                  url = "$BASE_URL/Library/VirtualFolders?name=$(${pkgs.jq}/bin/jq -rn --arg n \"${libraryName}\" '\$n|@uri')&collectionType=${libraryCfg.collectionType}&refreshLibrary=true";
                  apiKeyHeader = "Authorization";
                  headers = {
                    "Content-Type" = "application/json";
                  };
                  data = "@${libraryConfigFiles.${libraryName}}";
                  extraArgs = "-w \"\\n%{http_code}\"";
                }
              })

              CREATE_HTTP_CODE=$(http_status "$CREATE_RESPONSE")

              echo "Create library response (HTTP $CREATE_HTTP_CODE)"
              require_http_success "$CREATE_HTTP_CODE" "create library ${libraryName}"

              echo "Successfully created library: ${libraryName}"
            else
              echo "Library ${libraryName} already exists, checking for updates..."

              EXISTING_COLLECTION_TYPE=$(echo "$EXISTING_LIBRARY" | ${pkgs.jq}/bin/jq -r '.CollectionType // "unknown"')
              EXISTING_ITEM_ID=$(echo "$EXISTING_LIBRARY" | ${pkgs.jq}/bin/jq -r '.ItemId')
              EXISTING_PATHS=$(echo "$EXISTING_LIBRARY" | ${pkgs.jq}/bin/jq -c '.Locations // []')

              echo "Existing CollectionType: $EXISTING_COLLECTION_TYPE"
              echo "Existing ItemId: $EXISTING_ITEM_ID"
              echo "Existing Paths: $EXISTING_PATHS"

              if [ "$EXISTING_COLLECTION_TYPE" = "${libraryCfg.collectionType}" ]; then
                echo "Updating library options for: ${libraryName}"

                UPDATE_PAYLOAD=$(cat <<EOF
        {
          "Id": "$EXISTING_ITEM_ID",
          "LibraryOptions": $(cat ${
            libraryConfigFiles.${libraryName}
          } | ${pkgs.jq}/bin/jq '.LibraryOptions')
        }
        EOF
        )

                UPDATE_RESPONSE=$(${
                  mkSecureCurl authUtil.token {
                    method = "POST";
                    url = "$BASE_URL/Library/VirtualFolders/LibraryOptions";
                    apiKeyHeader = "Authorization";
                    headers = {
                      "Content-Type" = "application/json";
                    };
                    data = "$UPDATE_PAYLOAD";
                    extraArgs = "-w \"\\n%{http_code}\"";
                  }
                })

                UPDATE_HTTP_CODE=$(http_status "$UPDATE_RESPONSE")

                echo "Update library options response (HTTP $UPDATE_HTTP_CODE)"
                require_http_success "$UPDATE_HTTP_CODE" "update library options for ${libraryName}"

                CONFIGURED_PATHS=$(cat <<'EOF'
        ${builtins.toJSON libraryCfg.paths}
        EOF
        )

                echo "Configured paths: $CONFIGURED_PATHS"

                echo "$EXISTING_PATHS" | ${pkgs.jq}/bin/jq -r '.[]' | while IFS= read -r existing_path; do
                  if ! echo "$CONFIGURED_PATHS" | ${pkgs.jq}/bin/jq -e --arg path "$existing_path" 'index($path)' >/dev/null 2>&1; then
                    echo "Removing path: $existing_path"
                    REMOVE_PATH_RESPONSE=$(${
                      mkSecureCurl authUtil.token {
                        method = "DELETE";
                        url = "$BASE_URL/Library/VirtualFolders/Paths?name=$(${pkgs.jq}/bin/jq -rn --arg n \"${libraryName}\" '\$n|@uri')&path=$(${pkgs.jq}/bin/jq -rn --arg p \"$existing_path\" '\$p|@uri')";
                        apiKeyHeader = "Authorization";
                        extraArgs = "-w \"\\n%{http_code}\"";
                      }
                    })

                    REMOVE_PATH_HTTP_CODE=$(http_status "$REMOVE_PATH_RESPONSE")
                    warn_http_failure "$REMOVE_PATH_HTTP_CODE" "remove path $existing_path from library ${libraryName}" || true
                  fi
                done

                echo "$CONFIGURED_PATHS" | ${pkgs.jq}/bin/jq -r '.[]' | while IFS= read -r configured_path; do
                  if ! echo "$EXISTING_PATHS" | ${pkgs.jq}/bin/jq -e --arg path "$configured_path" 'index($path)' >/dev/null 2>&1; then
                    echo "Creating path: $configured_path"
                    mkdir -p "$configured_path"
                    echo "Adding path: $configured_path"
                    ADD_PATH_PAYLOAD=$(${pkgs.jq}/bin/jq -n --arg name "${libraryName}" --arg path "$configured_path" '{Name: $name, Path: $path}')

                    ADD_PATH_RESPONSE=$(${
                      mkSecureCurl authUtil.token {
                        method = "POST";
                        url = "$BASE_URL/Library/VirtualFolders/Paths";
                        apiKeyHeader = "Authorization";
                        headers = {
                          "Content-Type" = "application/json";
                        };
                        data = "$ADD_PATH_PAYLOAD";
                        extraArgs = "-w \"\\n%{http_code}\"";
                      }
                    })

                    ADD_PATH_HTTP_CODE=$(http_status "$ADD_PATH_RESPONSE")
                    warn_http_failure "$ADD_PATH_HTTP_CODE" "add path $configured_path to library ${libraryName}" || true
                  fi
                done

                echo "Successfully updated library: ${libraryName}"
              else
                echo "CollectionType changed from $EXISTING_COLLECTION_TYPE to ${libraryCfg.collectionType}, recreating library..."

                DELETE_RESPONSE=$(${
                  mkSecureCurl authUtil.token {
                    method = "DELETE";
                    url = "$BASE_URL/Library/VirtualFolders?name=$(${pkgs.jq}/bin/jq -rn --arg n \"${libraryName}\" '\$n|@uri')";
                    apiKeyHeader = "Authorization";
                    extraArgs = "-w \"\\n%{http_code}\"";
                  }
                })

                DELETE_HTTP_CODE=$(http_status "$DELETE_RESPONSE")
                require_http_success "$DELETE_HTTP_CODE" "delete library ${libraryName} for recreate"

                CREATE_RESPONSE=$(${
                  mkSecureCurl authUtil.token {
                    method = "POST";
                    url = "$BASE_URL/Library/VirtualFolders?name=$(${pkgs.jq}/bin/jq -rn --arg n \"${libraryName}\" '\$n|@uri')&collectionType=${libraryCfg.collectionType}&refreshLibrary=true";
                    apiKeyHeader = "Authorization";
                    headers = {
                      "Content-Type" = "application/json";
                    };
                    data = "@${libraryConfigFiles.${libraryName}}";
                    extraArgs = "-w \"\\n%{http_code}\"";
                  }
                })

                CREATE_HTTP_CODE=$(http_status "$CREATE_RESPONSE")
                require_http_success "$CREATE_HTTP_CODE" "recreate library ${libraryName}"

                echo "Successfully recreated library: ${libraryName}"
              fi
            fi
      '') cfg.libraries
    )}

    echo "$CONFIGURED_NAMES" > "$STATE_FILE"
    echo "Library configuration completed successfully"
  '';
}
