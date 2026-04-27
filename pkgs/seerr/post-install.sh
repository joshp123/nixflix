mkdir -p "$out/bin"
makeWrapper '@nodejs@/bin/node' "$out/bin/seerr" \
  --add-flags "$out/share/dist/index.js" \
  --chdir "$out/share" \
  --set NODE_ENV production
