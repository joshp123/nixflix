pushd node_modules/.pnpm/sqlite3@5.1.7/node_modules/sqlite3
node-gyp rebuild --verbose --build-from-source --sqlite="$npm_config_sqlite" --nodedir="$npm_config_nodedir"
popd
