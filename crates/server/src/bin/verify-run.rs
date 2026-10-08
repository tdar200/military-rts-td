//! `verify-run <file>`: re-simulates a recorded replay headless and checks it
//! against the file's own `END` line (Task 25).
//!
//! Prints `ticks <n> hash <h> expected <e> score <s> expected <x> MATCH|MISMATCH`
//! and exits 0 on a match, 1 on a mismatch, and 2 when the file cannot be
//! verified at all: unreadable or not a regular file, malformed (see
//! [`rts_server::bridge_protocol::verify`]), over the replay caps (more than
//! `REPLAY_MAX_TICK_LINES` lines in one tick or `REPLAY_MAX_LINES` in all),
//! recorded under another balance, or recorded on another sim build (its
//! `sim=` fingerprint differs from this build's, or it has none). A stale
//! replay is never reported as a MISMATCH: this build might play it
//! differently, so it proves nothing either way.
//!
//! A MATCH certifies consistency and score, not fog legality: see the replay
//! notes in [`rts_server::bridge_protocol`].

use std::path::Path;

use rts_server::bridge_protocol::{read_replay_text, verify};

/// The exit code and the text for `args` (the arguments after the program
/// name): the report line on stdout, or a message for stderr.
fn run(args: &[String]) -> (i32, String) {
    let [file] = args else {
        return (2, "usage: verify-run <replay file>".to_owned());
    };
    let report = read_replay_text(Path::new(file)).and_then(|text| verify(&text));
    match report {
        Ok(r) => (
            i32::from(!r.ok()),
            format!(
                "ticks {} hash {} expected {} score {} expected {} {}",
                r.ticks,
                r.hash,
                r.expected_hash,
                r.score,
                r.expected_score,
                if r.ok() { "MATCH" } else { "MISMATCH" }
            ),
        ),
        Err(message) => (2, format!("verify-run: {file}: {message}")),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (code, text) = run(&args);
    if code == 2 {
        eprintln!("{text}");
    } else {
        println!("{text}");
    }
    std::process::exit(code);
}

#[cfg(test)]
mod tests {
    use super::run;
    use rts_core::game::scenario::Scenario;
    use rts_server::bridge_protocol::{
        accept_lines, build_match, sim_fingerprint, step_frame, MatchConfig, ReplayRecorder,
        REPLAY_MAX_TICK_LINES,
    };
    use std::path::PathBuf;

    /// A folder under the workspace `target/` for one test.
    fn scratch(name: &str) -> PathBuf {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target/tmp")
            .join(format!("verify-run-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// A short Kestrel recording (two `stop` lines) through the bridge's frame body.
    fn record(dir: &std::path::Path) -> PathBuf {
        let cfg = MatchConfig {
            seed: 41,
            replay_dir: Some(dir.to_path_buf()),
            ..MatchConfig::boot(Scenario::KestrelReach)
        };
        let mut sim = build_match(&cfg);
        let mut recorder = ReplayRecorder::new();
        let path = recorder.start(&cfg, true, &sim).unwrap().unwrap();
        for frame in 0..120 {
            let lines = if frame % 50 == 7 {
                vec!["stop,1".to_owned()]
            } else {
                Vec::new()
            };
            step_frame(
                &mut sim,
                cfg.scenario,
                accept_lines(lines, |_| true),
                &mut recorder,
            )
            .unwrap();
        }
        recorder.stop(&sim).unwrap();
        path
    }

    #[test]
    fn verify_run_exits_0_on_match_1_on_mismatch_and_2_on_a_bad_file() {
        let dir = scratch("exits");
        let path = record(&dir);
        let file = path.display().to_string();
        let (code, line) = run(std::slice::from_ref(&file));
        assert_eq!(code, 0, "{line}");
        assert!(line.starts_with("ticks 120 hash "), "{line}");
        assert!(line.ends_with(" MATCH"), "{line}");

        let text = std::fs::read_to_string(&path).unwrap();
        let (body, _) = text.rsplit_once("END").unwrap();
        let tampered = dir.join("tampered.rpl");
        std::fs::write(&tampered, format!("{body}END 120 1 0\n")).unwrap();
        let (code, line) = run(&[tampered.display().to_string()]);
        assert_eq!(code, 1, "{line}");
        assert!(
            line.ends_with(" expected 1 score 0 expected 0 MISMATCH"),
            "{line}"
        );

        let no_magic = dir.join("no-magic.rpl");
        std::fs::write(&no_magic, text.replacen("RPL1", "RPL9", 1)).unwrap();
        let (code, message) = run(&[no_magic.display().to_string()]);
        assert_eq!(code, 2, "{message}");
        assert!(message.contains("RPL1"), "{message}");

        // P4 review I1: a replay from another sim build (or from before
        // replays named their build) is unverifiable, never a MISMATCH.
        let here = format!("sim={}\n", sim_fingerprint());
        assert!(text.contains(&here), "{text}");
        let stale = dir.join("stale.rpl");
        let other = format!("sim={}\n", sim_fingerprint() ^ 1);
        std::fs::write(&stale, text.replacen(&here, &other, 1)).unwrap();
        let (code, message) = run(&[stale.display().to_string()]);
        assert_eq!(code, 2, "{message}");
        assert!(message.contains("another sim build"), "{message}");
        let unnamed = dir.join("unnamed.rpl");
        std::fs::write(&unnamed, text.replacen(&here, "", 1)).unwrap();
        let (code, message) = run(&[unnamed.display().to_string()]);
        assert_eq!(code, 2, "{message}");
        assert!(message.contains("no sim= line"), "{message}");

        // P4 review M3: one tick past the cap is refused before any stepping.
        let flood = dir.join("flood.rpl");
        let extra = "T 119 stop,1\n".repeat(REPLAY_MAX_TICK_LINES + 1);
        let (head, end) = text.rsplit_once("END").unwrap();
        std::fs::write(&flood, format!("{head}{extra}END{end}")).unwrap();
        let (code, message) = run(&[flood.display().to_string()]);
        assert_eq!(code, 2, "{message}");
        assert!(message.contains("lines in one tick"), "{message}");

        assert_eq!(run(&[dir.join("missing.rpl").display().to_string()]).0, 2);
        assert_eq!(run(&[]).0, 2);
        assert_eq!(run(&[file.clone(), file]).0, 2);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
