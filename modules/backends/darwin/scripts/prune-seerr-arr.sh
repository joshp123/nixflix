#!/usr/bin/env bash
set -euo pipefail

usage="usage: prune-seerr-arr.sh CURL JQ SEERR_URL SETTINGS_JSON KIND CONFIGURED_NAMES_JSON"

curl_bin="${1:?$usage}"
jq_bin="${2:?$usage}"
seerr_url="${3:?$usage}"
settings_json="${4:?$usage}"
kind="${5:?$usage}"
configured_names_json="${6:?$usage}"

case "$kind" in
  radarr | sonarr) ;;
  *)
    echo "Unsupported Seerr Arr kind: $kind" >&2
    exit 1
    ;;
esac

api_key="$("$jq_bin" -r '.main.apiKey // empty' "$settings_json")"
if [ -z "$api_key" ]; then
  echo "Seerr API key is missing in $settings_json" >&2
  exit 1
fi

existing="$("$curl_bin" -fsS \
  --max-time 30 \
  -H "X-Api-Key: $api_key" \
  "$seerr_url/api/v1/settings/$kind")"

ids_to_delete="$(echo "$existing" | "$jq_bin" -r \
  --slurpfile configured "$configured_names_json" \
  '.[] | select((.name as $name | $configured[0] | index($name)) | not) | .id')"

for server_id in $ids_to_delete; do
  echo "Deleting unmanaged Seerr $kind integration: $server_id"
  "$curl_bin" -fsS -X DELETE \
    --max-time 30 \
    -H "X-Api-Key: $api_key" \
    "$seerr_url/api/v1/settings/$kind/$server_id" >/dev/null
done

echo "Seerr $kind prune completed"
