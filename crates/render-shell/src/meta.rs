//! Persistent cross-run meta-progression (shell-only).
//!
//! Currently a single value: the best number of survival waves the player has
//! reached, shown on the survival run-summary. Stored as a tiny text file on
//! native targets; on web it's a no-op (browser storage would need an extra
//! dependency — a future enhancement). This never touches the deterministic sim.

/// The player's best survival wave count, or 0 if none recorded.
#[must_use]
pub fn best_waves() -> u32 {
    read_best()
}

/// Records `waves` as the new best if it beats the stored value; returns the best.
pub fn record_waves(waves: u32) -> u32 {
    let best = read_best().max(waves);
    write_best(best);
    best
}

#[cfg(not(target_arch = "wasm32"))]
fn save_path() -> std::path::PathBuf {
    let dir = std::env::var_os("HOME").map_or_else(|| std::path::PathBuf::from("."), Into::into);
    std::path::Path::new(&dir).join(".stellar_front_best")
}

#[cfg(not(target_arch = "wasm32"))]
fn read_best() -> u32 {
    std::fs::read_to_string(save_path())
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0)
}

#[cfg(not(target_arch = "wasm32"))]
fn write_best(best: u32) {
    // Best-effort: a failed write just means no high-score persistence.
    let _ = std::fs::write(save_path(), best.to_string());
}

// On web, persistence is a no-op until browser storage is wired up.
#[cfg(target_arch = "wasm32")]
fn read_best() -> u32 {
    0
}

#[cfg(target_arch = "wasm32")]
fn write_best(_best: u32) {}
