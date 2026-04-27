#!/usr/bin/env bash
set -euo pipefail

state_dir="${1:?usage: activate-seerr.sh STATE_DIR LOG_DIR USER GROUP}"
log_dir="${2:?usage: activate-seerr.sh STATE_DIR LOG_DIR USER GROUP}"
user="${3:?usage: activate-seerr.sh STATE_DIR LOG_DIR USER GROUP}"
group="${4:?usage: activate-seerr.sh STATE_DIR LOG_DIR USER GROUP}"

mkdir -p "$state_dir" "$log_dir"
chown -R "$user:$group" "$state_dir"
