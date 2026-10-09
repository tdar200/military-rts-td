#!/usr/bin/env bash
# usage: tools/release/package.sh [linux|windows|all]   (default: linux)
#
# Builds a player package of Ascension (plan 2026-10-07-kestrel-depth, Task 28):
#   1. checks everything the chosen platforms need BEFORE building anything: the Godot 4.7.2 export templates and,
#      for Windows, the x86_64-pc-windows-gnu Rust target and the MinGW linker. A missing piece stops the script with
#      a message naming it. Nothing is downloaded or installed here; that is the developer's decision.
#   2. builds godot-bridge in release (offline) and checks it reports the project version;
#   3. exports the game headless with the preset ("Linux" or "Windows Desktop" in godot3d/export_presets.cfg);
#   4. checks the pack with tools/release/pck.py (no tests, tools, runtime, gallery, docs or .uid files in it; the game
#      files present) and refuses to package a pack that fails;
#   5. puts the bridge beside the executable (exec bit set), the licence texts in licenses/, writes VERSION, and
#      archives build/ascension-<version>-linux-x86_64.tar.gz (Windows: build/ascension-<version>-windows-x86_64.zip).
# The export runs on a staged copy of godot3d/ (BUILD_DIR/.stage, removed afterwards): Godot's editor-mode export
# writes .uid files beside scripts and stamps uids into resources, and none of that may touch the working tree.
#
# Environment (all optional):
#   GODOT       Godot 4.7.2 binary (default tools/godot/Godot_v4.7.2-stable_linux.x86_64)
#   BUILD_DIR   where packages go (default <repo>/build, gitignored)
#   BRIDGE      a prebuilt Linux godot-bridge to use instead of building one
#   BRIDGE_EXE  a prebuilt godot-bridge.exe to use instead of cross-building one (skips the Rust target and MinGW checks)
#   CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER  the MinGW linker (Cargo's own variable; default x86_64-w64-mingw32-gcc)
# Templates are looked up where Godot looks: ${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENGINE="4.7.2.stable"
GODOT="${GODOT:-$ROOT/tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
TEMPLATES="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$ENGINE"
WIN_TARGET="x86_64-pc-windows-gnu"
WIN_LINKER="${CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER:-x86_64-w64-mingw32-gcc}"

usage() { echo "usage: tools/release/package.sh [linux|windows|all]" >&2; exit 2; }
fail() { echo "package.sh: $*" >&2; exit 1; }

[ $# -le 1 ] || usage
MODE="${1:-linux}"
case "$MODE" in
  linux) PLATFORMS=(linux) ;;
  windows) PLATFORMS=(windows) ;;
  all) PLATFORMS=(linux windows) ;;
  *) usage ;;
esac

# ---- one version: project.godot config/version must equal the Cargo workspace version
VERSION="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$ROOT/godot3d/project.godot")"
CARGO_VERSION="$(awk '/^\[workspace.package\]/{w=1; next} /^\[/{w=0} w && /^version *=/{gsub(/[" ]/, "", $0); sub(/version=/, ""); print; exit}' "$ROOT/Cargo.toml")"
[ -n "$VERSION" ] || fail "godot3d/project.godot has no config/version"
[ "$VERSION" = "$CARGO_VERSION" ] || fail "godot3d/project.godot says $VERSION but the Cargo workspace says ${CARGO_VERSION:-nothing}"

# ---- preflight: every platform's needs, before anything is built
template_for() { case "$1" in linux) echo linux_release.x86_64 ;; windows) echo windows_release_x86_64.exe ;; esac; }
missing=()
for p in "${PLATFORMS[@]}"; do
  t="$TEMPLATES/$(template_for "$p")"
  [ -f "$t" ] || missing+=("$t")
done
if [ ${#missing[@]} -gt 0 ]; then
  {
    echo "package.sh: Godot export templates for $ENGINE are not installed. Missing:"
    printf '  %s\n' "${missing[@]}"
    echo "Install them from the Godot 4.7.2 release page (Godot_v4.7.2-stable_export_templates.tpz) into"
    echo "  $TEMPLATES/"
    echo "(the .tpz is a zip; its templates/ folder's files go there). Nothing was built."
  } >&2
  exit 1
fi
[ -x "$GODOT" ] || fail "Godot binary not found or not executable: $GODOT (set GODOT=...)"
for p in "${PLATFORMS[@]}"; do
  [ "$p" = windows ] && [ -z "${BRIDGE_EXE:-}" ] || continue
  if ! rustup target list --installed 2>/dev/null | grep -qx "$WIN_TARGET"; then
    fail "the Rust target $WIN_TARGET is not installed (it builds godot-bridge.exe). Install it with:
  rustup target add $WIN_TARGET
or set BRIDGE_EXE=<path to a godot-bridge.exe built elsewhere>. Nothing was built."
  fi
  if ! command -v "$WIN_LINKER" >/dev/null 2>&1; then
    fail "the MinGW linker $WIN_LINKER was not found (Cargo links godot-bridge.exe with it). On Debian or Ubuntu it
comes with the gcc-mingw-w64-x86-64 package; or set CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=<linker>.
Nothing was built."
  fi
done
command -v python3 >/dev/null 2>&1 || fail "python3 is needed to check the exported pack"

# ---- the export works on a staged copy (with the import cache, so nothing is re-imported); the dev runtime dir
# (snapshots, flags, command packets) is left behind, and the presets' filters keep the rest of the dev files out
STAGE="$BUILD_DIR/.stage"
stage_project() {
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -a "$ROOT/godot3d" "$STAGE/godot3d"
  rm -rf "$STAGE/godot3d/runtime"
}
trap 'rm -rf "$STAGE"' EXIT

licences() { # $1 = package dir
  mkdir -p "$1/licenses"
  cp "$ROOT"/godot3d/assets/licenses/*.txt "$ROOT/godot3d/assets/fonts/FONT-LICENSES.md" "$1/licenses/"
}

export_game() { # $1 = preset, $2 = output executable
  echo "package.sh: exporting \"$1\" to $2"
  "$GODOT" --headless --path "$STAGE/godot3d" --export-release "$1" "$2"
  [ -f "$2" ] || fail "Godot did not write $2"
  local pack="${2%.*}.pck"
  [ -f "$pack" ] || fail "Godot did not write the pack $pack"
  python3 "$ROOT/tools/release/pck.py" check "$pack" || fail "the exported pack $pack fails its check (above); nothing was archived"
}

package_linux() {
  local bridge="${BRIDGE:-}"
  if [ -z "$bridge" ]; then
    (cd "$ROOT" && cargo build --release --offline -p rts-server --bin godot-bridge)
    bridge="$ROOT/target/release/godot-bridge"
  fi
  local reported
  reported="$("$bridge" --version)" || fail "$bridge --version failed"
  [ "$reported" = "$VERSION" ] || fail "godot-bridge reports version $reported, the project is $VERSION"
  local name="ascension-$VERSION-linux-x86_64"
  local out="$BUILD_DIR/$name"
  rm -rf "$out" "$BUILD_DIR/$name.tar.gz"
  mkdir -p "$out"
  export_game "Linux" "$out/ascension.x86_64"
  cp "$bridge" "$out/godot-bridge"
  chmod +x "$out/godot-bridge" "$out/ascension.x86_64"
  licences "$out"
  echo "$VERSION" > "$out/VERSION"
  tar -C "$BUILD_DIR" -czf "$BUILD_DIR/$name.tar.gz" "$name"
  echo "package.sh: wrote $BUILD_DIR/$name.tar.gz ($(du -h "$BUILD_DIR/$name.tar.gz" | cut -f1))"
}

package_windows() {
  local bridge="${BRIDGE_EXE:-}"
  if [ -z "$bridge" ]; then
    (cd "$ROOT" && CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="$WIN_LINKER" \
      cargo build --release --offline --target "$WIN_TARGET" -p rts-server --bin godot-bridge)
    bridge="$ROOT/target/$WIN_TARGET/release/godot-bridge.exe"
  fi
  [ -f "$bridge" ] || fail "no godot-bridge.exe at $bridge"
  local name="ascension-$VERSION-windows-x86_64"
  local out="$BUILD_DIR/$name"
  rm -rf "$out" "$BUILD_DIR/$name.zip"
  mkdir -p "$out"
  export_game "Windows Desktop" "$out/ascension.exe"
  cp "$bridge" "$out/godot-bridge.exe"
  licences "$out"
  echo "$VERSION" > "$out/VERSION"
  (cd "$BUILD_DIR" && python3 -m zipfile -c "$name.zip" "$name")
  echo "package.sh: wrote $BUILD_DIR/$name.zip ($(du -h "$BUILD_DIR/$name.zip" | cut -f1)); test it on Windows before upload"
}

mkdir -p "$BUILD_DIR"
stage_project
for p in "${PLATFORMS[@]}"; do
  "package_$p"
done
