#!/usr/bin/env bash
set -euo pipefail

curl_bin="${1:?usage: configure-seerr-discover.sh CURL JQ BASE_URL SETTINGS_JSON ENABLE_BUILT_IN_SLIDERS}"
jq_bin="${2:?usage: configure-seerr-discover.sh CURL JQ BASE_URL SETTINGS_JSON ENABLE_BUILT_IN_SLIDERS}"
base_url="${3:?usage: configure-seerr-discover.sh CURL JQ BASE_URL SETTINGS_JSON ENABLE_BUILT_IN_SLIDERS}"
settings_json="${4:?usage: configure-seerr-discover.sh CURL JQ BASE_URL SETTINGS_JSON ENABLE_BUILT_IN_SLIDERS}"
enable_built_in_sliders="${5:?usage: configure-seerr-discover.sh CURL JQ BASE_URL SETTINGS_JSON ENABLE_BUILT_IN_SLIDERS}"

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

sliders="$("$curl_bin" -fsS \
  --max-time 30 \
  -H "X-Api-Key: $api_key" \
  "$base_url/api/v1/settings/discover")"

payload="$(echo "$sliders" | "$jq_bin" --arg enabled "$enable_built_in_sliders" '
  map(.enabled = ($enabled == "true"))
')"

response="$("$curl_bin" -sS -X POST \
  --max-time 30 \
  -H "X-Api-Key: $api_key" \
  -H "Content-Type: application/json" \
  -d "$payload" \
  -w "\n%{http_code}" \
  "$base_url/api/v1/settings/discover")"

http_code="$(echo "$response" | tail -n1)"
if [ "$http_code" != "200" ] && [ "$http_code" != "201" ] && [ "$http_code" != "204" ]; then
  echo "Failed to configure Seerr discover sliders (HTTP $http_code)" >&2
  echo "$response" | sed '$d' >&2
  exit 1
fi

echo "Seerr discover sliders configured: enableBuiltInSliders=$enable_built_in_sliders"
