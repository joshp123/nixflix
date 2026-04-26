runHook preInstall

export HOME="$TMPDIR"
bin_path="$(swift build -c release --product NixflixSupervisor --show-bin-path --disable-sandbox)"
app="$out/Applications/NixflixSupervisor.app"
mkdir -p "$app/Contents/MacOS"
install -m 0755 "$bin_path/NixflixSupervisor" "$app/Contents/MacOS/NixflixSupervisor"
install -m 0644 Info.plist "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"

runHook postInstall
