#!/usr/bin/env bash
set -euo pipefail

state_dir="$1"
template_file="$2"
config_dir="$state_dir/config"
config_file="$config_dir/config.yaml"
jq_bin="@jq@"

mkdir -p "$config_dir"

if [ "${BAZARR_REQUIRE_OPENSUBTITLES:-0}" = "1" ] &&
  { [ -z "${BAZARR_OPENSUBTITLES_USERNAME:-}" ] || [ -z "${BAZARR_OPENSUBTITLES_PASSWORD:-}" ]; }; then
  echo "OpenSubtitles.com is configured, but username or password is empty" >&2
  exit 1
fi

"$jq_bin" \
  --arg sonarr_api_key "$BAZARR_SONARR_API_KEY" \
  --arg radarr_api_key "$BAZARR_RADARR_API_KEY" \
  --arg opensubtitles_username "${BAZARR_OPENSUBTITLES_USERNAME:-}" \
  --arg opensubtitles_password "${BAZARR_OPENSUBTITLES_PASSWORD:-}" \
  '
    .sonarr.apikey = $sonarr_api_key
    | .radarr.apikey = $radarr_api_key
    | .opensubtitlescom.username = $opensubtitles_username
    | .opensubtitlescom.password = $opensubtitles_password
  ' "$template_file" > "$config_file"
