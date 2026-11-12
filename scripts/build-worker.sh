#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 ]] || { echo "Usage: $0 /path/to/worker image:tag" >&2; exit 2; }
cd "$1"
[[ -f package-lock.json ]] || { echo 'Run npm install (with open-orange@1.0.1) and commit package-lock.json first.' >&2; exit 1; }
npm ci
# Call the installed, locked version rather than downloading through npx.
./node_modules/.bin/orange deploy --dry-run --outdir .open-orange/deploy
exec docker build --platform linux/amd64 -f .open-orange/deploy/Dockerfile -t "$2" .open-orange/deploy/context
