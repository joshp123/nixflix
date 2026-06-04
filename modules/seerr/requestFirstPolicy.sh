set -euo pipefail

: "${SEERR_BASE_URL:?}"
: "${SEERR_SETTINGS_JSON:?}"
: "${SEERR_DB:?}"
: "${SEERR_USER_SETTINGS_JSON:?}"
: "${SEERR_MANAGED_USERS_JSON:?}"
: "${SEERR_DISCOVER_ENABLED_TYPES_JSON:?}"
: "${SEERR_DISCOVER_KNOWN_TYPES_JSON:?}"
: "${SEERR_RADARR_TARGETS_JSON:?}"
: "${SEERR_SONARR_TARGETS_JSON:?}"
: "${SEERR_PLEX_HOSTNAME:?}"
: "${SEERR_PLEX_PORT:?}"
: "${SEERR_PLEX_USE_SSL:?}"
: "${SEERR_PLEX_WEB_APP_URL:=}"

fail() {
  printf 'seerr-request-first-policy: %s\n' "$*" >&2
  exit 1
}

read_required_file() {
  local file="$1"
  [ -s "$file" ] || fail "required file is missing or empty: $file"
  tr -d '\n' < "$file"
}

seerr_api_key="$(jq -er '.main.apiKey // empty' "$SEERR_SETTINGS_JSON")"
[ -n "$seerr_api_key" ] || fail "restored Seerr settings.json does not contain main.apiKey"

jq -e '.main.mediaServerType == 1' "$SEERR_SETTINGS_JSON" >/dev/null \
  || fail "restored Seerr settings are not Plex-backed"

admin_plex_token_count() {
  sqlite3 "$SEERR_DB" \
    "select count(*) from user where id = 1 and plexToken is not null and length(plexToken) > 0;" \
    2>/dev/null || printf '0'
}

verify_admin_plex_token() {
  local reason="$1"
  local count

  count="$(admin_plex_token_count)"
  [ "$count" -ge 1 ] || fail "$reason"
}

verify_admin_plex_token "restored Seerr admin Plex token is missing"

echo "Waiting for Seerr at $SEERR_BASE_URL"
for attempt in $(seq 1 60); do
  if curl -fsS --max-time 5 "$SEERR_BASE_URL/api/v1/status" >/dev/null 2>&1; then
    break
  fi
  [ "$attempt" -lt 60 ] || fail "timed out waiting for Seerr"
  sleep 2
done

seerr_get() {
  curl -fsS --max-time 30 -H "X-Api-Key: $seerr_api_key" "$SEERR_BASE_URL$1"
}

seerr_write_json() {
  local method="$1"
  local path="$2"
  local payload="$3"
  local response
  local http_code

  response="$(
    curl -sS -X "$method" \
      --max-time 30 \
      -H "X-Api-Key: $seerr_api_key" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      -w "\n%{http_code}" \
      "$SEERR_BASE_URL$path"
  )"
  http_code="$(printf '%s\n' "$response" | tail -n1)"
  case "$http_code" in
    200 | 201 | 204) ;;
    *) fail "Seerr $method $path failed with HTTP $http_code" ;;
  esac
}

json_equal() {
  local left="$1"
  local right="$2"

  jq -e --argjson left "$left" --argjson right "$right" -n '$left == $right' >/dev/null
}

write_json_if_changed() {
  local method="$1"
  local path="$2"
  local current_payload="$3"
  local desired_payload="$4"
  local label="$5"

  if json_equal "$current_payload" "$desired_payload"; then
    echo "$label already applied"
  else
    seerr_write_json "$method" "$path" "$desired_payload"
    echo "$label applied"
  fi
}

plex_current="$(seerr_get /api/v1/settings/plex)"
plex_payload="$(
  printf '%s' "$plex_current" | jq \
    --arg ip "$SEERR_PLEX_HOSTNAME" \
    --arg port "$SEERR_PLEX_PORT" \
    --arg useSsl "$SEERR_PLEX_USE_SSL" \
    --arg webAppUrl "$SEERR_PLEX_WEB_APP_URL" \
    '. + {
      ip: $ip,
      port: ($port | tonumber),
      useSsl: ($useSsl == "true"),
      webAppUrl: $webAppUrl
    }'
)"
write_json_if_changed POST /api/v1/settings/plex "$plex_current" "$plex_payload" "Seerr Plex endpoint policy"
verify_admin_plex_token "Seerr admin Plex token was lost after Plex endpoint policy write"

apply_user_policy() {
  local user_settings_policy
  local main_current
  local user_settings_payload
  local managed_user_count
  local users_response

  user_settings_policy="$(cat "$SEERR_USER_SETTINGS_JSON")"
  main_current="$(seerr_get /api/v1/settings/main)"
  user_settings_payload="$(
    jq -n --argjson current "$main_current" --argjson policy "$user_settings_policy" '$current + $policy'
  )"
  write_json_if_changed POST /api/v1/settings/main "$main_current" "$user_settings_payload" "Seerr default user policy"

  managed_user_count="$(jq 'length' "$SEERR_MANAGED_USERS_JSON")"
  if [ "$managed_user_count" -gt 0 ]; then
    users_response="$(seerr_get '/api/v1/user?take=1000&skip=0')"
    jq -c 'to_entries[]' "$SEERR_MANAGED_USERS_JSON" | while read -r user_entry; do
      email="$(printf '%s' "$user_entry" | jq -r '.value.email')"
      permissions="$(printf '%s' "$user_entry" | jq -r '.value.permissions')"
      matches="$(printf '%s' "$users_response" | jq --arg email "$email" '[.results[] | select(.email == $email)]')"
      match_count="$(printf '%s' "$matches" | jq 'length')"
      [ "$match_count" -eq 1 ] || fail "expected exactly one Seerr user for $email, found $match_count"
      user_id="$(printf '%s' "$matches" | jq -r '.[0].id')"
      payload="$(jq -nc --argjson permissions "$permissions" '{permissions: $permissions}')"
      seerr_write_json POST "/api/v1/user/$user_id/settings/permissions" "$payload"
      echo "Seerr managed-user policy applied: $email"
    done
  fi
}

enabled_type_count="$(jq 'length' "$SEERR_DISCOVER_ENABLED_TYPES_JSON")"
if [ "$enabled_type_count" -gt 0 ]; then
  sliders="$(seerr_get /api/v1/settings/discover)"
  unknown_type_count="$(
    printf '%s' "$sliders" | jq --slurpfile knownTypes "$SEERR_DISCOVER_KNOWN_TYPES_JSON" \
      '[.[].type | select(($knownTypes[0] | index(.)) == null)] | length'
  )"
  [ "$unknown_type_count" -eq 0 ] || fail "Seerr discover response contains unknown slider types"
  payload="$(
    printf '%s' "$sliders" | jq --slurpfile enabledTypes "$SEERR_DISCOVER_ENABLED_TYPES_JSON" \
      'map(.enabled = (.type as $type | $enabledTypes[0] | index($type) != null))'
  )"
  write_json_if_changed POST /api/v1/settings/discover "$sliders" "$payload" "Seerr discover slider policy"
fi

arr_api_get() {
  local base_url="$1"
  local api_key="$2"
  local path="$3"
  curl -fsS --max-time 30 -H "X-Api-Key: $api_key" "$base_url$path"
}

target_base_url() {
  local target="$1"
  local scheme
  local hostname
  local port
  local base_url

  scheme="$(printf '%s' "$target" | jq -r 'if .useSsl then "https" else "http" end')"
  hostname="$(printf '%s' "$target" | jq -r '.hostname')"
  port="$(printf '%s' "$target" | jq -r '.port')"
  base_url="$(printf '%s' "$target" | jq -r '.baseUrl')"
  printf '%s://%s:%s%s' "$scheme" "$hostname" "$port" "$base_url"
}

resolve_profile_id() {
  local app_base_url="$1"
  local api_key="$2"
  local profile_name="$3"
  local profiles
  local matches
  local match_count

  profiles="$(arr_api_get "$app_base_url" "$api_key" /api/v3/qualityprofile)"
  matches="$(printf '%s' "$profiles" | jq --arg name "$profile_name" '[.[] | select(.name == $name)]')"
  match_count="$(printf '%s' "$matches" | jq 'length')"
  [ "$match_count" -eq 1 ] || fail "expected exactly one Arr profile named $profile_name at $app_base_url, found $match_count"
  printf '%s' "$matches" | jq -r '.[0].id'
}

find_existing_server() {
  local kind="$1"
  local target="$2"
  local existing
  local matches
  local match_count
  local alias_conflicts
  local alias_count
  local matched_id
  local name
  local hostname
  local port
  local base_url
  local use_ssl

  name="$(printf '%s' "$target" | jq -r '.name')"
  hostname="$(printf '%s' "$target" | jq -r '.hostname')"
  port="$(printf '%s' "$target" | jq -r '.port')"
  base_url="$(printf '%s' "$target" | jq -r '(.baseUrl // "") | if . == "/" then "" else sub("/+$"; "") end')"
  use_ssl="$(printf '%s' "$target" | jq -r '(.useSsl // false | tostring)')"
  existing="$(seerr_get "/api/v1/settings/$kind")"
  matches="$(
    printf '%s' "$existing" | jq \
      --arg name "$name" \
      --arg hostname "$hostname" \
      --arg port "$port" \
      --arg baseUrl "$base_url" \
      --arg useSsl "$use_ssl" \
      '
      def normBase: if . == null or . == "/" then "" else (. | tostring | sub("/+$"; "")) end;
      [.[] | select(
        .name == $name or
        (
          .hostname == $hostname and
          (.port | tostring) == $port and
          ((.baseUrl // "" | normBase) == $baseUrl) and
          ((.useSsl // false | tostring) == $useSsl)
        )
      )]'
  )"
  match_count="$(printf '%s' "$matches" | jq 'length')"
  [ "$match_count" -le 1 ] || fail "ambiguous existing Seerr $kind target for $name"
  matched_id=""
  if [ "$match_count" -eq 1 ]; then
    matched_id="$(printf '%s' "$matches" | jq -r '.[0].id | tostring')"
  fi

  alias_conflicts="$(
    printf '%s' "$existing" | jq \
      --arg hostname "$hostname" \
      --arg port "$port" \
      --arg baseUrl "$base_url" \
      --arg useSsl "$use_ssl" \
      --arg matchedId "$matched_id" \
      '
      def normBase: if . == null or . == "/" then "" else (. | tostring | sub("/+$"; "")) end;
      def localHost($host): $host == "127.0.0.1" or $host == "localhost";
      [.[] | select(
        (.id | tostring) != $matchedId and
        localHost(.hostname) and
        localHost($hostname) and
        (.port | tostring) == $port and
        ((.baseUrl // "" | normBase) == $baseUrl) and
        ((.useSsl // false | tostring) == $useSsl)
      )]'
  )"
  alias_count="$(printf '%s' "$alias_conflicts" | jq 'length')"
  [ "$alias_count" -eq 0 ] || fail "refusing to create duplicate Seerr $kind target for local endpoint $base_url"
  if [ "$match_count" -eq 1 ]; then
    printf '%s' "$matches" | jq -c '.[0]'
  fi
}

ensure_no_search_enabled_servers() {
  local kind="$1"
  local existing
  local unsafe
  local unsafe_count
  local unsafe_names

  existing="$(seerr_get "/api/v1/settings/$kind")"
  unsafe="$(printf '%s' "$existing" | jq '[.[] | select(.preventSearch != true)]')"
  unsafe_count="$(printf '%s' "$unsafe" | jq 'length')"
  if [ "$unsafe_count" -gt 0 ]; then
    unsafe_names="$(printf '%s' "$unsafe" | jq -r 'map(.name // (.id | tostring)) | join(", ")')"
    fail "existing Seerr $kind target(s) permit search-on-request: $unsafe_names"
  fi
}

configure_radarr_target() {
  local target="$1"
  local name
  local api_key_file
  local api_key
  local app_base_url
  local profile_id
  local existing_server
  local existing_id
  local target_payload
  local payload

  name="$(printf '%s' "$target" | jq -r '.name')"
  api_key_file="$(printf '%s' "$target" | jq -r '.apiKeyFile')"
  api_key="$(read_required_file "$api_key_file")"
  app_base_url="$(target_base_url "$target")"
  profile_id="$(resolve_profile_id "$app_base_url" "$api_key" "$(printf '%s' "$target" | jq -r '.activeProfileName')")"
  existing_server="$(find_existing_server radarr "$target")"
  target_payload="$(
    printf '%s' "$target" | jq \
      --arg apiKey "$api_key" \
      --argjson profileId "$profile_id" \
      'del(.apiKeyFile) + {
        apiKey: $apiKey,
        activeProfileId: $profileId
      }'
  )"
  if [ -n "$existing_server" ]; then
    existing_id="$(printf '%s' "$existing_server" | jq -r '.id')"
    payload="$(jq -n --argjson existing "$existing_server" --argjson desired "$target_payload" '$existing + $desired')"
    write_json_if_changed PUT "/api/v1/settings/radarr/$existing_id" "$existing_server" "$payload" "Seerr Radarr target policy: $name"
  else
    payload="$target_payload"
    seerr_write_json POST /api/v1/settings/radarr "$payload"
    echo "Seerr Radarr target policy created: $name"
  fi
}

configure_sonarr_target() {
  local target="$1"
  local name
  local api_key_file
  local api_key
  local app_base_url
  local profile_id
  local anime_profile_id
  local existing_server
  local existing_id
  local target_payload
  local payload

  name="$(printf '%s' "$target" | jq -r '.name')"
  api_key_file="$(printf '%s' "$target" | jq -r '.apiKeyFile')"
  api_key="$(read_required_file "$api_key_file")"
  app_base_url="$(target_base_url "$target")"
  profile_id="$(resolve_profile_id "$app_base_url" "$api_key" "$(printf '%s' "$target" | jq -r '.activeProfileName')")"
  anime_profile_id="$(resolve_profile_id "$app_base_url" "$api_key" "$(printf '%s' "$target" | jq -r '.activeAnimeProfileName')")"
  existing_server="$(find_existing_server sonarr "$target")"
  target_payload="$(
    printf '%s' "$target" | jq \
      --arg apiKey "$api_key" \
      --argjson profileId "$profile_id" \
      --argjson animeProfileId "$anime_profile_id" \
      'del(.apiKeyFile) + {
        apiKey: $apiKey,
        activeProfileId: $profileId,
        activeAnimeProfileId: $animeProfileId
      }'
  )"
  if [ -n "$existing_server" ]; then
    existing_id="$(printf '%s' "$existing_server" | jq -r '.id')"
    payload="$(jq -n --argjson existing "$existing_server" --argjson desired "$target_payload" '$existing + $desired')"
    write_json_if_changed PUT "/api/v1/settings/sonarr/$existing_id" "$existing_server" "$payload" "Seerr Sonarr target policy: $name"
  else
    payload="$target_payload"
    seerr_write_json POST /api/v1/settings/sonarr "$payload"
    echo "Seerr Sonarr target policy created: $name"
  fi
}

radarr_target_count="$(jq 'length' "$SEERR_RADARR_TARGETS_JSON")"
if [ "$radarr_target_count" -gt 0 ]; then
  jq -c '.[]' "$SEERR_RADARR_TARGETS_JSON" | while read -r target; do
    configure_radarr_target "$target"
  done
fi
ensure_no_search_enabled_servers radarr

sonarr_target_count="$(jq 'length' "$SEERR_SONARR_TARGETS_JSON")"
if [ "$sonarr_target_count" -gt 0 ]; then
  jq -c '.[]' "$SEERR_SONARR_TARGETS_JSON" | while read -r target; do
    configure_sonarr_target "$target"
  done
fi
ensure_no_search_enabled_servers sonarr

apply_user_policy

echo "Seerr request-first policy completed"
