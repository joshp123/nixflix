runHook preBuild
export HOME="$TMPDIR"
swift build -c release --product NixflixSupervisor --disable-sandbox
runHook postBuild
