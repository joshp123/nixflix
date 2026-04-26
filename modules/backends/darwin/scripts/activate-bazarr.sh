#!/usr/bin/env bash
set -euo pipefail

state_dir="${1:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
log_dir="${2:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
user="${3:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
group="${4:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
write_config="${5:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
config_template="${6:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
sonarr_api_key_mode="${7:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
sonarr_api_key_value="${8:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
radarr_api_key_mode="${9:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
radarr_api_key_value="${10:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
opensubtitles_username_mode="${11:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
opensubtitles_username_value="${12:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
opensubtitles_password_mode="${13:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"
opensubtitles_password_value="${14:?usage: activate-bazarr.sh STATE_DIR LOG_DIR USER GROUP WRITE_CONFIG TEMPLATE ...}"

read_value() {
  case "$1" in
    empty)
      ;;
    file)
      cat "$2"
      ;;
    literal)
      printf '%s' "$2"
      ;;
    *)
      echo "unsupported Bazarr secret mode: $1" >&2
      exit 1
      ;;
  esac
}

mkdir -p "$state_dir" "$log_dir"

export BAZARR_SONARR_API_KEY
export BAZARR_RADARR_API_KEY
export BAZARR_OPENSUBTITLES_USERNAME
export BAZARR_OPENSUBTITLES_PASSWORD
export BAZARR_REQUIRE_OPENSUBTITLES="0"
BAZARR_SONARR_API_KEY="$(read_value "$sonarr_api_key_mode" "$sonarr_api_key_value")"
BAZARR_RADARR_API_KEY="$(read_value "$radarr_api_key_mode" "$radarr_api_key_value")"
BAZARR_OPENSUBTITLES_USERNAME="$(read_value "$opensubtitles_username_mode" "$opensubtitles_username_value")"
BAZARR_OPENSUBTITLES_PASSWORD="$(read_value "$opensubtitles_password_mode" "$opensubtitles_password_value")"
if [ "$opensubtitles_username_mode" != "empty" ] || [ "$opensubtitles_password_mode" != "empty" ]; then
  BAZARR_REQUIRE_OPENSUBTITLES="1"
fi

/bin/bash "$write_config" "$state_dir" "$config_template"
chown -R "$user:$group" "$state_dir"

/usr/bin/pkill -u "$user" -f '/bazarr.py ' >/dev/null 2>&1 || true
if pids="$(/usr/bin/pgrep -U "$user" -f '/bazarr/main.py ' 2>/dev/null)"; then
  printf '%s\n' "$pids" | while IFS= read -r pid; do
    kill "$pid" >/dev/null 2>&1 || true
  done
fi
