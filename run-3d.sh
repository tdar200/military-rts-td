#!/usr/bin/env bash
set -euo pipefail

GAME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="$GAME_ROOT/tools/godot/Godot_v4.7.2-stable_linux.x86_64"
BRIDGE_BIN="$GAME_ROOT/target/release/godot-bridge"
SNAPSHOT="$GAME_ROOT/godot3d/runtime/snapshot.json"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot 4.7.2 is missing at: $GODOT_BIN" >&2
  exit 1
fi

# Hybrid Linux laptops can otherwise select Mesa/Intel despite an available
# NVIDIA GPU. Preserve explicit user configuration; allow an integrated override.
if [[ "${EARTHFRONT_GPU:-auto}" != "integrated" ]] && command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD:-1}"
  export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
fi

cargo build --release -p rts-server --bin godot-bridge --manifest-path "$GAME_ROOT/Cargo.toml"

# SCENARIO=kestrel ./run-3d.sh starts the bridge on Kestrel Reach; unset (or "survival") is the default Survival map.
BRIDGE_ARGS=()
if [[ -n "${SCENARIO:-}" ]]; then
  BRIDGE_ARGS+=(--scenario "$SCENARIO")
fi

"$BRIDGE_BIN" "${BRIDGE_ARGS[@]}" "$SNAPSHOT" &
BRIDGE_PID=$!
cleanup() {
  kill "$BRIDGE_PID" 2>/dev/null || true
  wait "$BRIDGE_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

"$GODOT_BIN" --path "$GAME_ROOT/godot3d" "$@"
