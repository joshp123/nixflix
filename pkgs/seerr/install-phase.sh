runHook preInstall

mkdir -p "$out/share"
cp -r -t "$out/share" .next node_modules dist public package.json seerr-api.yml

runHook postInstall
