#!/usr/bin/env bash
set -euo pipefail

state_dir="${1:?usage: write-arr-config.sh STATE_DIR API_KEY BIND_ADDRESS BRANCH}"
api_key="${2:?usage: write-arr-config.sh STATE_DIR API_KEY BIND_ADDRESS BRANCH}"
bind_address="${3:?usage: write-arr-config.sh STATE_DIR API_KEY BIND_ADDRESS BRANCH}"
branch="${4:?usage: write-arr-config.sh STATE_DIR API_KEY BIND_ADDRESS BRANCH}"
config_file="$state_dir/config.xml"

mkdir -p "$state_dir"

if [ -f "$config_file" ]; then
  tmp="$(mktemp)"
  awk -v api_key="$api_key" '
    /<ApiKey>/ {
      print "  <ApiKey>" api_key "</ApiKey>"
      next
    }
    { print }
  ' "$config_file" > "$tmp"
  mv "$tmp" "$config_file"
  exit 0
fi

cat > "$config_file" <<EOF
<Config>
  <BindAddress>$bind_address</BindAddress>
  <SslPort>6969</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>False</LaunchBrowser>
  <ApiKey>$api_key</ApiKey>
  <Branch>$branch</Branch>
  <LogLevel>info</LogLevel>
  <SslCertPath></SslCertPath>
  <SslCertPassword></SslCertPassword>
</Config>
EOF
