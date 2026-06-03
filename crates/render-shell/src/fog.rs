//! Shell-side fog of war (the player's hidden-information layer).
//!
//! Each frame this recomputes which tiles the human can currently see from the
//! positions + vision radius of their living units and buildings, accumulating an
//! "explored" memory. The renderer shrouds unseen tiles and hides enemy pieces
//! that aren't currently visible. It reads only the public `Sim` view and never
//! feeds back into the simulation, so it has no effect on determinism — the AI
//! (sim-side) is unaffected; this is purely what the player is shown.

use rts_core::game::sim::{EntityKindView, PlayerId, Sim};

const HUMAN: PlayerId = PlayerId(0);
/// Vision radius (tiles) for a unit and for a building.
const VISION_UNIT: f32 = 5.0;
const VISION_BLDG: f32 = 7.0;

/// Per-tile visibility for the human player.
pub struct Fog {
    w: i32,
    h: i32,
    explored: Vec<bool>,
    visible: Vec<bool>,
}

impl Fog {
    /// Creates an all-unseen fog sized to the map.
    #[must_use]
    pub fn new(width: u16, height: u16) -> Self {
        let n = usize::from(width) * usize::from(height);
        Self {
            w: i32::from(width),
            h: i32::from(height),
            explored: vec![false; n],
            visible: vec![false; n],
        }
    }

    const fn idx(&self, col: i32, row: i32) -> usize {
        (row * self.w + col) as usize
    }

    /// Recomputes currently-visible tiles from the human's living entities and
    /// folds them into the explored memory.
    pub fn update(&mut self, sim: &Sim) {
        for v in &mut self.visible {
            *v = false;
        }
        for e in sim.views() {
            if e.owner != HUMAN {
                continue;
            }
            let radius = if matches!(e.kind, EntityKindView::Building(_)) {
                VISION_BLDG
            } else {
                VISION_UNIT
            };
            let ex = e.pos.x.to_bits() as f32 / 65536.0;
            let ey = e.pos.y.to_bits() as f32 / 65536.0;
            let r2 = radius * radius;
            let c0 = (ex - radius).floor() as i32;
            let c1 = (ex + radius).ceil() as i32;
            let r0 = (ey - radius).floor() as i32;
            let r1 = (ey + radius).ceil() as i32;
            for row in r0..=r1 {
                for col in c0..=c1 {
                    if col < 0 || row < 0 || col >= self.w || row >= self.h {
                        continue;
                    }
                    let dx = col as f32 - ex;
                    let dy = row as f32 - ey;
                    if dx * dx + dy * dy <= r2 {
                        let i = self.idx(col, row);
                        self.visible[i] = true;
                        self.explored[i] = true;
                    }
                }
            }
        }
    }

    /// Whether the human can currently see tile `(col, row)`.
    #[must_use]
    pub fn visible(&self, col: u16, row: u16) -> bool {
        let (c, r) = (i32::from(col), i32::from(row));
        if c >= self.w || r >= self.h {
            return false;
        }
        self.visible[self.idx(c, r)]
    }

    /// Whether the human has ever seen tile `(col, row)`.
    #[must_use]
    pub fn explored(&self, col: u16, row: u16) -> bool {
        let (c, r) = (i32::from(col), i32::from(row));
        if c >= self.w || r >= self.h {
            return false;
        }
        self.explored[self.idx(c, r)]
    }
}
