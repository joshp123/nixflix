runHook preBuild

pnpm build
CI=true pnpm prune --prod --ignore-scripts
rm -rf .next/cache

find node_modules -xtype l -delete

runHook postBuild
