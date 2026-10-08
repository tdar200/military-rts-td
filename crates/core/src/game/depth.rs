//! Kestrel depth rules: RTS combat, match shape and run mode, isolated behind
//! the narrow `depth` flag that only [`crate::game::scenario::kestrel_reach`]
//! sets. Every behaviour here checks [`Sim::is_depth`] (`earthfront && depth`),
//! never `earthfront` alone: the Survival map also enables Earthfront and must
//! stay byte-identical.
//!
//! State lives in [`DepthUnit`] (one per entity, `Entity::dp`) and
//! [`DepthGlobal`] (`Sim::dg`). Both are folded into [`Sim::state_hash`] only
//! when depth is on. Later tasks append fields at the END of each struct and
//! their hash writes at the END of its `hash_into`, in task order, never
//! reordering.

use super::Sim;
use crate::hash::Fnv;

/// Per-entity depth state. Empty until the combat tasks append to it.
#[derive(Clone, Debug, Default)]
pub(super) struct DepthUnit {}

impl DepthUnit {
    /// Folds this entity's depth state into the world hash (depth on only).
    #[allow(
        clippy::unused_self,
        clippy::needless_pass_by_ref_mut,
        clippy::missing_const_for_fn,
        reason = "the fixed hash call site exists before the fields that later depth tasks append here"
    )]
    pub(super) fn hash_into(&self, h: &mut Fnv) {
        let _ = h;
    }
}

/// World-wide depth state. Empty until the match-shape tasks append to it.
#[derive(Clone, Debug, Default)]
pub(super) struct DepthGlobal {}

impl DepthGlobal {
    /// Folds the global depth state into the world hash (depth on only).
    #[allow(
        clippy::unused_self,
        clippy::needless_pass_by_ref_mut,
        clippy::missing_const_for_fn,
        reason = "the fixed hash call site exists before the fields that later depth tasks append here"
    )]
    pub(super) fn hash_into(&self, h: &mut Fnv) {
        let _ = h;
    }
}

impl Sim {
    /// Turns on the Kestrel depth rules. Called only by
    /// [`crate::game::scenario::kestrel_reach`], after `enable_earthfront`;
    /// depth means nothing without Earthfront (see [`Sim::is_depth`]).
    #[allow(
        clippy::missing_const_for_fn,
        reason = "later depth tasks draw deterministic match state here"
    )]
    pub fn enable_depth(&mut self) {
        self.depth = true;
    }

    /// Whether the Kestrel depth rules are active: Earthfront AND depth. Every
    /// depth behaviour and every depth hash write checks this, never
    /// `earthfront` alone.
    #[must_use]
    pub const fn is_depth(&self) -> bool {
        self.earthfront && self.depth
    }
}

#[cfg(test)]
mod tests {
    use crate::game::hex;
    use crate::game::scenario::{
        kestrel_reach, kestrel_reach_classic, lane_defense, survival, Scenario,
    };
    use crate::game::sim::{Command, EntityKindView, PlayerId, Sim};
    use crate::game::stats::UnitKind;
    use alloc::vec::Vec;

    /// `survival(7)` after 3000 host ticks, measured at 503fd7c (before the
    /// depth flag existed). Every later core task re-runs this unchanged.
    const SURVIVAL_PIN: u64 = 1_622_883_436_588_820_810;
    /// Classic Kestrel (`kestrel_reach_classic(3)`, no depth) after 6000 host
    /// ticks, measured at 503fd7c with the bridge's command list.
    const KESTREL_CLASSIC_PIN: u64 = 2_849_524_003_663_712_283;

    #[test]
    fn depth_is_only_enabled_by_kestrel() {
        assert!(kestrel_reach(3).is_depth());
        assert!(!survival(3).is_depth());
        assert!(!lane_defense(3).is_depth());
        assert!(!kestrel_reach_classic(3).is_depth());
    }

    #[test]
    fn survival_and_classic_kestrel_hashes_are_pinned_across_depth() {
        let mut s = survival(7);
        for _ in 0..3000 {
            let c = Scenario::Survival.host_commands(&s);
            s.step(&c);
        }
        assert_eq!(s.state_hash(), SURVIVAL_PIN);
        let mut k = kestrel_reach_classic(3);
        for _ in 0..6000 {
            let c = Scenario::KestrelReach.host_commands(&k);
            k.step(&c);
        }
        assert_eq!(k.state_hash(), KESTREL_CLASSIC_PIN);
    }

    /// Fixed player script exercising every depth command (later tasks append theirs).
    pub(super) fn scripted_player(s: &Sim) -> Vec<Command> {
        let mut out = Vec::new();
        if s.tick() == 600 {
            for v in s.views().into_iter().filter(|v| {
                v.owner == PlayerId(0) && matches!(v.kind, EntityKindView::Unit(UnitKind::Infantry))
            }) {
                out.push(Command::AttackMove {
                    owner: PlayerId(0),
                    unit: v.id,
                    target: hex::center(20, 10),
                });
            }
        }
        out
    }

    #[test]
    fn same_inputs_twice_give_the_same_depth_hash_and_replay() {
        let run = || {
            let mut s = kestrel_reach(11);
            let mut log = Vec::new();
            for _ in 0..5000 {
                let mut c = Scenario::KestrelReach.host_commands(&s);
                c.extend(scripted_player(&s));
                s.step(&c);
                log.push(c);
            }
            (s.state_hash(), log)
        };
        let (a, log) = run();
        let (b, _) = run();
        assert_eq!(a, b);
        let mut r = kestrel_reach(11);
        for c in &log {
            r.step(c);
        }
        assert_eq!(r.state_hash(), a);
    }

    /// Host commands are a pure function of the world: building them never
    /// mutates the sim and asking twice gives the same list, so a replay that
    /// re-derives them per tick (the bridge, the tests, `verify-run`) and one
    /// that replays a recorded log reach the same hash, including from a save
    /// (a clone) taken mid-match just before the alien AI wakes up.
    #[test]
    fn host_commands_are_pure_and_replay_from_a_mid_match_save() {
        // Fixed step counts, never `while tick < n`: a decided Earthfront match
        // stops advancing its tick (the undefended base falls near t=5000).
        const STEPS: u32 = 6000;
        const SAVE_AT: u32 = 4000;
        let mut s = kestrel_reach(11);
        let mut save = None;
        let mut log = Vec::new();
        for step in 0..STEPS {
            let before = s.state_hash();
            let c = Scenario::KestrelReach.host_commands(&s);
            assert_eq!(s.state_hash(), before, "host_commands mutated the sim");
            assert_eq!(
                alloc::format!("{c:?}"),
                alloc::format!("{:?}", Scenario::KestrelReach.host_commands(&s)),
                "host_commands is not repeatable at tick {}",
                s.tick()
            );
            let mut c = c;
            c.extend(scripted_player(&s));
            if step == SAVE_AT {
                save = Some(s.clone());
            }
            if step >= SAVE_AT {
                log.push(c.clone());
            }
            s.step(&c);
        }
        assert!(
            s.waves_survived() > 0,
            "the horizon must reach the alien AI"
        );
        // Continue the save by re-deriving host commands live.
        let mut live = save.clone().expect("save taken");
        for _ in SAVE_AT..STEPS {
            let mut c = Scenario::KestrelReach.host_commands(&live);
            c.extend(scripted_player(&live));
            live.step(&c);
        }
        // Continue the save from the recorded log only.
        let mut logged = save.expect("save taken");
        for c in &log {
            logged.step(c);
        }
        assert_eq!(live.state_hash(), s.state_hash());
        assert_eq!(logged.state_hash(), s.state_hash());
    }

    /// Depth changes nothing about the starting world: the depth and classic
    /// Kestrel builds show the same entities, yet only the depth one hashes the
    /// depth state (its marker), so a depth replay can never verify against a
    /// classic world.
    #[test]
    fn depth_kestrel_starts_from_the_classic_world_but_hashes_apart() {
        let depth = kestrel_reach(3);
        let classic = kestrel_reach_classic(3);
        assert_eq!(
            alloc::format!("{:?}", depth.views()),
            alloc::format!("{:?}", classic.views())
        );
        assert_ne!(depth.state_hash(), classic.state_hash());
    }
}
