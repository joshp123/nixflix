#!/usr/bin/env bash
set -euo pipefail

usage="usage: configure-seerr-users.sh CURL JQ BASE_URL SETTINGS_JSON USER_SETTINGS_JSON MANAGED_USERS_JSON"
curl_bin="${1:?$usage}"
jq_bin="${2:?$usage}"
base_url="${3:?$usage}"
settings_json="${4:?$usage}"
user_settings_json="${5:?$usage}"
managed_users_json="${6:?$usage}"

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

users_response="$("$curl_bin" -sS \
  --max-time 30 \
  -H "X-Api-Key: $api_key" \
  "$base_url/api/v1/user?take=1000&skip=0")"

"$jq_bin" -c 'to_entries[]' "$managed_users_json" | while read -r user_entry; do
  email="$(printf '%s' "$user_entry" | "$jq_bin" -r '.value.email')"
  permissions="$(printf '%s' "$user_entry" | "$jq_bin" -r '.value.permissions')"

  user_id="$(printf '%s' "$users_response" | "$jq_bin" -r --arg email "$email" '.results[] | select(.email == $email) | .id' | head -n1)"
  if [ -z "$user_id" ]; then
    echo "Seerr user not found: $email" >&2
    exit 1
  fi

  response="$("$curl_bin" -sS -X POST \
    --max-time 30 \
    -H "X-Api-Key: $api_key" \
    -H "Content-Type: application/json" \
    -d "$("$jq_bin" -nc --argjson permissions "$permissions" '{permissions: $permissions}')" \
    -w "\n%{http_code}" \
    "$base_url/api/v1/user/$user_id/settings/permissions")"

  http_code="$(echo "$response" | tail -n1)"
  if [ "$http_code" != "200" ] && [ "$http_code" != "201" ] && [ "$http_code" != "204" ]; then
    echo "Failed to configure Seerr user permissions for $email (HTTP $http_code)" >&2
    echo "$response" | sed '$d' >&2
    exit 1
  fi

  echo "Seerr user permissions configured: $email"
done
