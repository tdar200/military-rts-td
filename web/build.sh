#!/usr/bin/env bash
# Build the web (wasm32) bundle and stage it next to index.html, then serve it.
#
#   ./web/build.sh           # debug build + serve on :8000
#   ./web/build.sh --release # optimized build (much smaller .wasm) + serve
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE_DIR="debug"
CARGO_FLAGS=()
if [[ "${1:-}" == "--release" ]]; then
  PROFILE_DIR="release"
  CARGO_FLAGS+=(--release)
fi

cargo build -p rts-render-shell --target wasm32-unknown-unknown "${CARGO_FLAGS[@]}"
cp "$ROOT/target/wasm32-unknown-unknown/$PROFILE_DIR/rts.wasm" "$ROOT/web/rts.wasm"

echo "Serving http://localhost:8000/ (Ctrl-C to stop)"
cd "$ROOT/web"
python3 -m http.server 8000
