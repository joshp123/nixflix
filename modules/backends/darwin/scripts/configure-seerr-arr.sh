#!/usr/bin/env bash
set -euo pipefail

usage="usage: configure-seerr-arr.sh CURL JQ SEERR_URL SETTINGS_JSON KIND CONFIG_JSON API_KEY_MODE API_KEY_VALUE"

curl_bin="${1:?$usage}"
jq_bin="${2:?$usage}"
seerr_url="${3:?$usage}"
settings_json="${4:?$usage}"
kind="${5:?$usage}"
config_json="${6:?$usage}"
api_key_mode="${7:?$usage}"
api_key_value="${8:?$usage}"

case "$kind" in
  radarr | sonarr) ;;
  *)
    echo "Unsupported Seerr Arr kind: $kind" >&2
    exit 1
    ;;
esac

case "$api_key_mode" in
  file)
    arr_api_key="$(cat "$api_key_value")"
    ;;
  literal)
    arr_api_key="$api_key_value"
    ;;
  *)
    echo "Unsupported API key mode: $api_key_mode" >&2
    exit 1
    ;;
esac

for attempt in $(seq 1 60); do
  if "$curl_bin" --retry 0 --connect-timeout 2 --max-time 5 -fsS -o /dev/null "$seerr_url/api/v1/status"; then
    break
  fi
  if [ "$attempt" -eq 60 ]; then
    echo "Timed out waiting for Seerr at $seerr_url" >&2
    exit 1
  fi
  sleep 2
done

seerr_api_key="$("$jq_bin" -r '.main.apiKey // empty' "$settings_json")"
if [ -z "$seerr_api_key" ]; then
  echo "Seerr API key is missing in $settings_json" >&2
  exit 1
fi

name="$("$jq_bin" -r '.name' "$config_json")"
profile_name="$("$jq_bin" -r '.activeProfileName // empty' "$config_json")"

test_payload="$("$jq_bin" \
  --arg apiKey "$arr_api_key" \
  '. | {
    hostname,
    port,
    apiKey: $apiKey,
    useSsl,
    baseUrl
  }' "$config_json")"

echo "Testing Seerr $kind integration: $name"
test_response="$("$curl_bin" -sS -X POST \
  --max-time 30 \
  -H "X-Api-Key: $seerr_api_key" \
  -H "Content-Type: application/json" \
  -d "$test_payload" \
  -w "\n%{http_code}" \
  "$seerr_url/api/v1/settings/$kind/test")"
test_http_code="$(echo "$test_response" | tail -n1)"
test_body="$(echo "$test_response" | sed '$d')"

if [ "$test_http_code" != "200" ]; then
  echo "Seerr $kind connection test failed (HTTP $test_http_code)" >&2
  echo "$test_body" >&2
  exit 1
fi

if [ -n "$profile_name" ]; then
  profile_id="$(echo "$test_body" | "$jq_bin" -r --arg name "$profile_name" 'first(.profiles[] | select(.name == $name) | .id) // empty')"
else
  profile_id="$(echo "$test_body" | "$jq_bin" -r '.profiles[0].id')"
  profile_name="$(echo "$test_body" | "$jq_bin" -r '.profiles[0].name')"
fi

if [ -z "$profile_id" ] || [ "$profile_id" = "null" ]; then
  echo "Could not find $kind profile: ${profile_name:-first available}" >&2
  echo "$test_body" | "$jq_bin" -r '.profiles[] | "  - \(.name)"' >&2
  exit 1
fi

anime_profile_id="$profile_id"
anime_profile_name="$profile_name"
if [ "$kind" = "sonarr" ]; then
  requested_anime_profile="$("$jq_bin" -r '.activeAnimeProfileName // empty' "$config_json")"
  if [ -n "$requested_anime_profile" ]; then
    found_anime_profile_id="$(echo "$test_body" | "$jq_bin" -r --arg name "$requested_anime_profile" 'first(.profiles[] | select(.name == $name) | .id) // empty')"
    if [ -n "$found_anime_profile_id" ] && [ "$found_anime_profile_id" != "null" ]; then
      anime_profile_id="$found_anime_profile_id"
      anime_profile_name="$requested_anime_profile"
    fi
  fi
fi

payload="$("$jq_bin" \
  --arg apiKey "$arr_api_key" \
  --arg profileId "$profile_id" \
  --arg profileName "$profile_name" \
  --arg animeProfileId "$anime_profile_id" \
  --arg animeProfileName "$anime_profile_name" \
  --arg kind "$kind" \
  '. as $cfg
  | {
    name: $cfg.name,
    hostname: $cfg.hostname,
    port: $cfg.port,
    apiKey: $apiKey,
    useSsl: $cfg.useSsl,
    baseUrl: $cfg.baseUrl,
    activeProfileId: ($profileId | tonumber),
    activeProfileName: $profileName,
    activeDirectory: $cfg.activeDirectory,
    is4k: $cfg.is4k,
    isDefault: $cfg.isDefault,
    externalUrl: $cfg.externalUrl,
    syncEnabled: $cfg.syncEnabled,
    preventSearch: $cfg.preventSearch
  }
  | if $kind == "radarr" then
      . + {
        minimumAvailability: $cfg.minimumAvailability
      }
    else
      . + {
        activeAnimeProfileId: ($animeProfileId | tonumber),
        activeAnimeProfileName: $animeProfileName,
        activeAnimeDirectory: $cfg.activeAnimeDirectory,
        seriesType: $cfg.seriesType,
        animeSeriesType: $cfg.animeSeriesType,
        enableSeasonFolders: $cfg.enableSeasonFolders
      }
    end' "$config_json")"

existing="$("$curl_bin" -fsS \
  --max-time 30 \
  -H "X-Api-Key: $seerr_api_key" \
  "$seerr_url/api/v1/settings/$kind")"
existing_id="$(echo "$existing" | "$jq_bin" -r --arg name "$name" 'first(.[] | select(.name == $name) | .id) // empty')"

if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
  echo "Updating Seerr $kind integration: $name"
  response="$("$curl_bin" -sS -X PUT \
    --max-time 30 \
    -H "X-Api-Key: $seerr_api_key" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    -w "\n%{http_code}" \
    "$seerr_url/api/v1/settings/$kind/$existing_id")"
else
  echo "Creating Seerr $kind integration: $name"
  response="$("$curl_bin" -sS -X POST \
    --max-time 30 \
    -H "X-Api-Key: $seerr_api_key" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    -w "\n%{http_code}" \
    "$seerr_url/api/v1/settings/$kind")"
fi

http_code="$(echo "$response" | tail -n1)"
if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
  echo "Failed to configure Seerr $kind integration (HTTP $http_code)" >&2
  echo "$response" | sed '$d' >&2
  exit 1
fi

echo "Seerr $kind configuration completed: $name"
