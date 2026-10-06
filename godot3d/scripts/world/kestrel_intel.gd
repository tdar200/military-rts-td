extends RefCounted
## Kestrel Reach briefing intel (fix round after the final review, I1). Scenario Task 2 stages an alien probe on the east
## bank opposite the Wyllow Ford at PROBE_STAGE_TICK as "the first-minute warning that something is coming", but under
## the Task 6 fog of war that picket is outside human sight, so nothing showed before the probe struck. The client now
## gives the warning as scouting intel at the probe's scripted time: one toast and the existing alert sound, once per run.
## It reveals nothing the fog hides: the copy names only the ford (the briefing already does), and the game adds no
## minimap ring, no alert ping for Space and no camera move. Pure: the game holds the `given` latch.

## Mirrors crates/core/src/game/scenario.rs KESTREL_PROBE_STAGE_TICK (55 s): the probe leaves the holdfast for the picket.
## test_kestrel_intel.gd reads scenario.rs and fails if the two drift apart.
const PROBE_STAGE_TICK := 1650
## Mirrors scenario.rs KESTREL_PROBE_STRIKE_TICK (1:50): the probe crosses. A first poll past it says nothing (too late).
const PROBE_STRIKE_TICK := 3300
const PROBE_TITLE := "SCOUTS REPORT MOVEMENT NEAR THE FORD"
const PROBE_BODY := "AN ALIEN PROBE MAY CROSS BEFORE WAVE ONE"


## {given, fire}: `given` is the new latch for the game to keep, `fire` whether to warn on this snapshot. A tick before the
## stage tick (a fresh or restarted sim) re-arms; inside [PROBE_STAGE_TICK, PROBE_STRIKE_TICK) an unwarned run warns once;
## a re-delivered or later snapshot never repeats it.
static func probe_warning(tick: int, given: bool) -> Dictionary:
	if tick < PROBE_STAGE_TICK:
		return {"given": false, "fire": false}
	if given:
		return {"given": true, "fire": false}
	return {"given": true, "fire": tick < PROBE_STRIKE_TICK}
