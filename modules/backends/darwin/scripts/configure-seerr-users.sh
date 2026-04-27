#!/usr/bin/env bash
set -euo pipefail

curl_bin="${1:?usage: configure-seerr-users.sh CURL JQ BASE_URL SETTINGS_JSON USER_SETTINGS_JSON}"
jq_bin="${2:?usage: configure-seerr-users.sh CURL JQ BASE_URL SETTINGS_JSON USER_SETTINGS_JSON}"
base_url="${3:?usage: configure-seerr-users.sh CURL JQ BASE_URL SETTINGS_JSON USER_SETTINGS_JSON}"
settings_json="${4:?usage: configure-seerr-users.sh CURL JQ BASE_URL SETTINGS_JSON USER_SETTINGS_JSON}"
user_settings_json="${5:?usage: configure-seerr-users.sh CURL JQ BASE_URL SETTINGS_JSON USER_SETTINGS_JSON}"

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

payload="$(cat "$user_settings_json")"
response="$("$curl_bin" -sS -X POST \
  --max-time 30 \
  -H "X-Api-Key: $api_key" \
  -H "Content-Type: application/json" \
  -d "$payload" \
  -w "\n%{http_code}" \
  "$base_url/api/v1/settings/main")"

http_code="$(echo "$response" | tail -n1)"
if [ "$http_code" != "200" ] && [ "$http_code" != "201" ] && [ "$http_code" != "204" ]; then
  echo "Failed to configure Seerr user settings (HTTP $http_code)" >&2
  echo "$response" | sed '$d' >&2
  exit 1
fi

echo "Seerr user settings configured"
