#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
[[ $(pnpm --version) == 11.20.0 ]] || { echo 'Folio requires pnpm 11.20.0 and Node 24+.' >&2; exit 1; }
source_url=$(jq -r .repository "$repo/apps/folio/source.json")
revision=$(jq -r .revision "$repo/apps/folio/source.json")
orange=$(jq -r .openOrangeVersion "$repo/apps/folio/source.json")
image=$(jq -r .image "$repo/apps/folio/source.json")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git clone --quiet "$source_url" "$work/source"
cd "$work/source"
git checkout --quiet "$revision"
pnpm install --frozen-lockfile
pnpm typecheck
pnpm build
# Explicitly allow only the additional native build scripts required by Orange.
cat > pnpm-workspace.yaml <<'BUILDS'
allowBuilds:
  esbuild: true
  workerd: true
  better-sqlite3: true
  cbor-extract: true
  protobufjs: true
  '@google/genai': false
BUILDS
pnpm add -D "open-orange@$orange"
node --input-type=module - <<'JS'
import {readFileSync,writeFileSync} from 'node:fs';
const c=JSON.parse(readFileSync('wrangler.jsonc','utf8'));
c.name='folio-homelab';delete c.env;
c.d1_databases[0].database_id='folio-homelab-catalog';
c.r2_buckets[0].bucket_name='folio-homelab-originals';
c.vars={LOCAL_DEV:'true',PRIVATE_LIBRARY:'true',ALLOW_LOCAL_ADMIN:'false',ENABLE_REGISTRATION:'false'};
writeFileSync('wrangler.homelab.json',JSON.stringify(c,null,2)+'\n');
JS
pnpm exec orange deploy --dry-run --config wrangler.homelab.json --outdir .open-orange/deploy
docker build --platform linux/amd64 -f .open-orange/deploy/Dockerfile -t "$image" .open-orange/deploy/context
