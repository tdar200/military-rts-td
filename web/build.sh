#!/usr/bin/env bash
# Build the web (wasm32) bundle and stage it next to index.html, then serve it.
#
#   ./web/build.sh                      # debug build + serve on :8000
#   ./web/build.sh --release            # optimized build + serve
#   ./web/build.sh --release --no-serve # package-only CI/release check
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE_DIR="debug"
CARGO_FLAGS=()
SERVE=true
for arg in "$@"; do
  case "$arg" in
    --release)
      PROFILE_DIR="release"
      CARGO_FLAGS=(--release)
      ;;
    --no-serve) SERVE=false ;;
    *)
      echo "usage: $0 [--release] [--no-serve]" >&2
      exit 2
      ;;
  esac
done

# Web ships with audio: wasm uses WebAudio, so no system (ALSA) dependency.
cargo build -p rts-render-shell --target wasm32-unknown-unknown --features audio "${CARGO_FLAGS[@]}"
cp "$ROOT/target/wasm32-unknown-unknown/$PROFILE_DIR/rts.wasm" "$ROOT/web/rts.wasm"
# Vendor the exact Macroquad JS shim Cargo resolved for this build. Depending on
# the public sample CDN made a successful WASM build render as a black page when
# offline or when that host was unavailable. `cargo metadata` avoids accidentally
# copying a different registry version when several Macroquad releases are cached.
MQ_JS="$(cargo metadata --format-version 1 | python3 -c '
import json, os, sys
packages = json.load(sys.stdin)["packages"]
manifest = next(p["manifest_path"] for p in packages if p["name"] == "macroquad")
print(os.path.join(os.path.dirname(manifest), "js", "mq_js_bundle.js"))
')"
if [[ ! -f "$MQ_JS" ]]; then
  echo "error: could not locate resolved macroquad runtime at $MQ_JS" >&2
  exit 1
fi
cp "$MQ_JS" "$ROOT/web/mq_js_bundle.js"
# Ship only runtime sprites (not the 1.7 MB source atlas or legacy art), plus the
# fonts and audio, so the browser package stays lean and self-contained.
mkdir -p "$ROOT/web/assets"
find "$ROOT/web/assets" -maxdepth 1 -type f -name '*.png' -delete
for asset in infantry tank anti_armor helicopter harvester command_center \
  power_plant refinery barracks gun_turret aa_turret wall; do
  cp "$ROOT/assets/${asset}_v2.png" "$ROOT/web/assets/"
  cp "$ROOT/assets/alien_${asset}_v1.png" "$ROOT/web/assets/"
done
cp "$ROOT/assets/capital_v1.png" "$ROOT/web/assets/"
cp "$ROOT/assets/alien_capital_v1.png" "$ROOT/web/assets/"
for asset in rock_cluster scrub_cluster dead_tree sandbags wrecked_car \
  concrete_barriers floodlight crater ore_crystals alloy_crystals foundation \
  chain_fence; do
  cp "$ROOT/assets/${asset}_v1.png" "$ROOT/web/assets/"
done
cp -r "$ROOT/assets/fonts" "$ROOT/web/assets/"
cp -r "$ROOT/assets/audio" "$ROOT/web/assets/"

if [[ "$SERVE" == false ]]; then
  echo "Built self-contained web package in $ROOT/web"
  exit 0
fi

echo "Serving http://localhost:8000/ (Ctrl-C to stop)"
cd "$ROOT/web"
python3 -m http.server 8000
