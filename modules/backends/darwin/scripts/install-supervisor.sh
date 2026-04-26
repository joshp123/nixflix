#!/usr/bin/env bash
set -euo pipefail

supervisor_user="${1:?usage: install-supervisor.sh USER HOME LOG_DIR APP_SRC MANIFEST}"
user_home="${2:?usage: install-supervisor.sh USER HOME LOG_DIR APP_SRC MANIFEST}"
log_dir="${3:?usage: install-supervisor.sh USER HOME LOG_DIR APP_SRC MANIFEST}"
supervisor_app_src="${4:?usage: install-supervisor.sh USER HOME LOG_DIR APP_SRC MANIFEST}"
manifest="${5:?usage: install-supervisor.sh USER HOME LOG_DIR APP_SRC MANIFEST}"

app_path="/Applications/NixflixSupervisor.app"
manifest_dir="$user_home/Library/Application Support/nixflix"
stable_manifest="$manifest_dir/supervisor-manifest.json"

/bin/launchctl bootout system/com.jjpcodes.nixflix.supervisor >/dev/null 2>&1 || true
/bin/launchctl bootout system/com.jjpcodes.nixflix.supervisor-test-direct >/dev/null 2>&1 || true
rm -f /Library/LaunchDaemons/com.jjpcodes.nixflix.supervisor.plist
rm -f /Library/LaunchDaemons/com.jjpcodes.nixflix.supervisor-test-direct.plist

uid="$(id -u "$supervisor_user" 2>/dev/null || true)"
if [ -n "$uid" ]; then
  for label in \
    org.nixflix.qbittorrent \
    org.nixflix.sonarr \
    org.nixflix.sonarr-config \
    org.nixflix.sonarr-anime \
    org.nixflix.sonarr-anime-config \
    org.nixflix.radarr \
    org.nixflix.radarr-config \
    org.nixflix.prowlarr \
    org.nixflix.prowlarr-config; do
    /bin/launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
  done

  for plist in \
    org.nixflix.qbittorrent.plist \
    org.nixflix.sonarr.plist \
    org.nixflix.sonarr-config.plist \
    org.nixflix.sonarr-anime.plist \
    org.nixflix.sonarr-anime-config.plist \
    org.nixflix.radarr.plist \
    org.nixflix.radarr-config.plist \
    org.nixflix.prowlarr.plist \
    org.nixflix.prowlarr-config.plist; do
    rm -f "$user_home/Library/LaunchAgents/$plist"
  done

  /bin/launchctl bootout "gui/$uid" "$user_home/Library/LaunchAgents/com.jjpcodes.nixflix.supervisor.plist" >/dev/null 2>&1 || true
  /bin/launchctl bootout "gui/$uid" "$user_home/Library/LaunchAgents/com.jjpcodes.nixflix.supervisor-direct-agent.plist" >/dev/null 2>&1 || true
  rm -f "$user_home/Library/LaunchAgents/com.jjpcodes.nixflix.supervisor.plist"
  rm -f "$user_home/Library/LaunchAgents/com.jjpcodes.nixflix.supervisor-direct-agent.plist"
fi

/usr/bin/pkill -x NixflixSupervisor >/dev/null 2>&1 || true
/usr/bin/pkill -u "$supervisor_user" -x qbittorrent-nox >/dev/null 2>&1 || true
/usr/bin/pkill -u "$supervisor_user" -x Sonarr >/dev/null 2>&1 || true
/usr/bin/pkill -u "$supervisor_user" -x Radarr >/dev/null 2>&1 || true
/usr/bin/pkill -u "$supervisor_user" -x Prowlarr >/dev/null 2>&1 || true

rm -rf "$app_path"
cp -R "$supervisor_app_src" "$app_path"
chown -R root:wheel "$app_path"

mkdir -p "$log_dir"
chown -R "$supervisor_user:staff" "$log_dir"

mkdir -p "$manifest_dir"
cp "$manifest" "$stable_manifest"
chown -R "$supervisor_user:staff" "$manifest_dir"
chmod 0644 "$stable_manifest"

if [ -n "$uid" ] && /bin/launchctl print "gui/$uid" >/dev/null 2>&1; then
  /bin/launchctl asuser "$uid" /usr/bin/sudo -u "$supervisor_user" \
    "$app_path/Contents/MacOS/NixflixSupervisor" "$stable_manifest" \
    >> /var/log/nixflix-supervisor-bootstrap.log 2>&1 &
fi
