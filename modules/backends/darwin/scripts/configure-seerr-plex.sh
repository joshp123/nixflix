#!/usr/bin/env bash
set -euo pipefail

curl_bin="${1:?usage: configure-seerr-plex.sh CURL JQ BASE_URL SETTINGS_JSON HOST PORT USE_SSL WEB_APP_URL ENABLE_ALL LIBRARY_NAMES_JSON}"
jq_bin="${2:?usage: configure-seerr-plex.sh CURL JQ BASE_URL SETTINGS_JSON HOST PORT USE_SSL WEB_APP_URL ENABLE_ALL LIBRARY_NAMES_JSON}"
base_url="${3:?usage: configure-seerr-plex.sh CURL JQ BASE_URL SETTINGS_JSON HOST PORT USE_SSL WEB_APP_URL ENABLE_ALL LIBRARY_NAMES_JSON}"
settings_json="${4:?usage: configure-seerr-plex.sh CURL JQ BASE_URL SETTINGS_JSON HOST PORT USE_SSL WEB_APP_URL ENABLE_ALL LIBRARY_NAMES_JSON}"
plex_host="${5:?usage: configure-seerr-plex.sh CURL JQ BASE_URL SETTINGS_JSON HOST PORT USE_SSL WEB_APP_URL ENABLE_ALL LIBRARY_NAMES_JSON}"
plex_port="${6:?usage: configure-seerr-plex.sh CURL JQ BASE_URL SETTINGS_JSON HOST PORT USE_SSL WEB_APP_URL ENABLE_ALL LIBRARY_NAMES_JSON}"
plex_use_ssl="${7:?usage: configure-seerr-plex.sh CURL JQ BASE_URL SETTINGS_JSON HOST PORT USE_SSL WEB_APP_URL ENABLE_ALL LIBRARY_NAMES_JSON}"
plex_web_app_url="${8-}"
enable_all_libraries="${9:?usage: configure-seerr-plex.sh CURL JQ BASE_URL SETTINGS_JSON HOST PORT USE_SSL WEB_APP_URL ENABLE_ALL LIBRARY_NAMES_JSON}"
library_names_json="${10:?usage: configure-seerr-plex.sh CURL JQ BASE_URL SETTINGS_JSON HOST PORT USE_SSL WEB_APP_URL ENABLE_ALL LIBRARY_NAMES_JSON}"

for _attempt in $(seq 1 60); do
  if "$curl_bin" --retry 0 --connect-timeout 2 --max-time 5 -fsS -o /dev/null "$base_url/api/v1/status"; then
    break
  fi
  if [ "$_attempt" -eq 60 ]; then
    echo "Timed out waiting for Seerr at $base_url" >&2
    exit 1
  fi
  sleep 2
done

api_key="$("$jq_bin" -r '.main.apiKey // empty' "$settings_json")"
if [ -z "$api_key" ]; then
  echo "Seerr API key is missing in $settings_json" >&2
  exit 1
fi

plex_payload="$("$jq_bin" -n \
  --arg ip "$plex_host" \
  --arg port "$plex_port" \
  --arg useSsl "$plex_use_ssl" \
  --arg webAppUrl "$plex_web_app_url" \
  '{
    ip: $ip,
    port: ($port | tonumber),
    useSsl: ($useSsl == "true"),
    webAppUrl: $webAppUrl
  }')"

echo "Configuring Seerr Plex endpoint: $plex_host:$plex_port"
plex_response="$("$curl_bin" -sS -X POST \
  --max-time 30 \
  -H "X-Api-Key: $api_key" \
  -H "Content-Type: application/json" \
  -d "$plex_payload" \
  -w "\n%{http_code}" \
  "$base_url/api/v1/settings/plex")"
plex_http_code="$(echo "$plex_response" | tail -n1)"
if [ "$plex_http_code" != "200" ]; then
  echo "Failed to configure Seerr Plex endpoint (HTTP $plex_http_code)" >&2
  echo "$plex_response" | sed '$d' >&2
  exit 1
fi

libraries="$("$curl_bin" -fsS \
  --max-time 30 \
  -H "X-Api-Key: $api_key" \
  "$base_url/api/v1/settings/plex/library?sync=true")"

if [ "$enable_all_libraries" = "true" ]; then
  library_ids="$(echo "$libraries" | "$jq_bin" -r '.[].id' | paste -sd, -)"
else
  library_ids="$(echo "$libraries" | "$jq_bin" -r \
    --slurpfile names "$library_names_json" \
    '.[] | select(.name as $name | $names[0] | index($name)) | .id' | paste -sd, -)"
fi

if [ -z "$library_ids" ]; then
  echo "No Plex libraries matched Seerr configuration" >&2
  echo "$libraries" | "$jq_bin" -r '.[] | "  - \(.name) (\(.type))"' >&2
  exit 1
fi

echo "Enabling Seerr Plex libraries: $library_ids"
"$curl_bin" -fsS \
  --max-time 30 \
  -H "X-Api-Key: $api_key" \
  "$base_url/api/v1/settings/plex/library?enable=$library_ids" >/dev/null

"$curl_bin" -fsS -X POST \
  --max-time 30 \
  -H "X-Api-Key: $api_key" \
  -H "Content-Type: application/json" \
  -d '{"start":true}' \
  "$base_url/api/v1/settings/plex/sync" >/dev/null

"$curl_bin" -fsS -X POST \
  --max-time 30 \
  -H "X-Api-Key: $api_key" \
  -H "Content-Type: application/json" \
  "$base_url/api/v1/settings/initialize" >/dev/null

echo "Seerr Plex configuration completed"
