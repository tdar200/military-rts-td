# Mobile builds (Android / iOS)

The game is one codebase: the deterministic `rts-core` and the Macroquad
render/input shell compile to mobile the same way they compile to desktop and
web. Touch input is already handled in `crates/render-shell/src/input.rs`
(tap a friendly unit to select; tap empty ground to move) and feeds the **same**
`rts_core::Command` set as mouse/keyboard — the simulation is input-agnostic.

What remains for each store is *packaging*, which needs the platform SDK and
(for shipping) a developer account. None of that can run in a headless Linux CI
box, so it is documented here rather than executed.

## Android (via `cargo-apk`)

Build config lives in `crates/render-shell/Cargo.toml` under
`[package.metadata.android]`.

Prerequisites: Android SDK + NDK, and the Rust Android targets.

```bash
rustup target add aarch64-linux-android armv7-linux-androideabi
cargo install cargo-apk
# with ANDROID_HOME / ANDROID_NDK_HOME set:
cargo apk build -p rts-render-shell --release   # produces an APK
cargo apk run   -p rts-render-shell             # build, install, run on a device
```

To ship: create a Google Play account ($25 one-time), sign the AAB with a
release keystore, complete the IARC age rating, and submit.

## iOS (via miniquad + Xcode)

miniquad (under Macroquad) supports iOS, but the toolchain is macOS-only.

```bash
rustup target add aarch64-apple-ios
cargo build -p rts-render-shell --release --target aarch64-apple-ios
```

Then wrap the static library in an Xcode project (miniquad ships an iOS example
template), set up a provisioning profile and signing (Apple Developer Program,
$99/yr), handle safe-area insets, and submit through App Store Connect.

## Status in this repo

- ✅ Touch input mapped in the shared input-abstraction layer.
- ✅ Android `cargo-apk` metadata wired.
- ✅ Shell compiles for native desktop and `wasm32`.
- ⏳ Producing signed APK/IPA and store submission require the Android SDK/NDK
  and macOS/Xcode plus developer accounts (out of scope for the CI sandbox).
