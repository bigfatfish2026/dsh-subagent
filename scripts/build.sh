#!/usr/bin/env bash
# Build this override repo from the vendored upstream source.
#
# Produces the published artifact layout:
#   lib/index.js                  ESM bundle (tsdown, entry lib/types/index.js)
#   lib/types/**/*.js + *.d.ts    per-module tsc output (serves ./internal, ./client)
#   lib/typert.host.*             Typert artifacts, shipped pre-generated (typert/)
#   lib/typert.remote-client.*
#
# Usage: scripts/build.sh
#
# Notes
# - Build tooling lives in .build-tools (gitignored) so node_modules/ stays a
#   runtime-only link farm pointing at the host's dsh tree.
# - tsc runs with --noCheck: this package's type graph reaches every @deepseek-ai
#   host package, which does not fit in this Pi's heap (OOM at 4 GB). Emit itself
#   is unaffected; emitted JS/d.ts were verified byte-identical to npm's.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

BUILD_TOOLS=${BUILD_TOOLS:-$REPO_ROOT/.build-tools}
TSDOWN_VERSION=${TSDOWN_VERSION:-^0.22.2}
TYPESCRIPT_VERSION=${TYPESCRIPT_VERSION:-^6.0.3}

if [ ! -x "$BUILD_TOOLS/node_modules/.bin/tsc" ] || [ ! -x "$BUILD_TOOLS/node_modules/.bin/tsdown" ]; then
	echo "installing build tooling into $BUILD_TOOLS"
	npm install --prefix "$BUILD_TOOLS" --no-audit --no-fund \
		"typescript@$TYPESCRIPT_VERSION" "tsdown@$TSDOWN_VERSION"
fi

rm -rf lib
NODE_OPTIONS=${NODE_OPTIONS:---max-old-space-size=6144} \
	"$BUILD_TOOLS/node_modules/.bin/tsc" -p tsconfig.json --noCheck
"$BUILD_TOOLS/node_modules/.bin/tsdown" --config tsdown.config.ts

cp typert/typert.host.js typert/typert.host.d.ts \
	typert/typert.remote-client.js typert/typert.remote-client.d.ts lib/

for file in $(find lib -name '*.js' | sort); do
	node --check "$file"
done

echo "built: $(find lib -name '*.js' | wc -l) js files, $(find lib -name '*.d.ts' | wc -l) declaration files"
