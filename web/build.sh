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

# Web ships with audio: wasm uses WebAudio, so no system (ALSA) dependency.
cargo build -p rts-render-shell --target wasm32-unknown-unknown --features audio "${CARGO_FLAGS[@]}"
cp "$ROOT/target/wasm32-unknown-unknown/$PROFILE_DIR/rts.wasm" "$ROOT/web/rts.wasm"
# Ship the sprite + font + audio assets next to the page so the browser can fetch them.
mkdir -p "$ROOT/web/assets"
cp "$ROOT"/assets/*.png "$ROOT/web/assets/"
cp -r "$ROOT/assets/fonts" "$ROOT/web/assets/"
cp -r "$ROOT/assets/audio" "$ROOT/web/assets/"

echo "Serving http://localhost:8000/ (Ctrl-C to stop)"
cd "$ROOT/web"
python3 -m http.server 8000
