extends RefCounted
## The sim's combat tables, mirrored for the combat preview. Every value here is read from the Rust source by
## tests/test_combat_rules.gd, so a balance change there fails a test here instead of drifting silently.
##   damage_multiplier  crates/core/src/game/stats.rs   (damage type against armour class)
##   veterancy_factor   crates/core/src/game/sim.rs     (outgoing damage by rank)
##   UnitKind::stats    crates/core/src/game/stats.rs   (each unit's armour class and weapon damage type)
##   BuildingKind::base crates/core/src/game/stats.rs   (every building has Structure armour)

## Weapon damage type of each armed unit kind. The Harvester has no weapon (its damage is zero), so it is absent.
const DAMAGE_OF := {
	"Infantry": "Ballistic",
	"Tank": "Explosive",
	"AntiArmor": "AntiArmor",
	"Helicopter": "Ballistic",
	"Capital": "Explosive",
}

## Armour class of each unit kind. Buildings are all "Structure" (see armour_of).
const ARMOUR_OF := {
	"Infantry": "Flesh",
	"AntiArmor": "Flesh",
	"Tank": "Plated",
	"Helicopter": "Plated",
	"Capital": "Plated",
	"Harvester": "Plated",
}

## Every non-neutral pair of the matrix as [damage type, armour class, numerator, denominator]; any other pair is 1/1.
const MATRIX := [
	["Ballistic", "Flesh", 3, 2],
	["Explosive", "Structure", 3, 2],
	["Ballistic", "Plated", 1, 2],
	["AntiArmor", "Flesh", 1, 2],
	["AntiArmor", "Plated", 7, 4],
]

## Outgoing-damage bonus in percent for ranks 0 to 3 (rank 3 and above share the top value, as the sim's `_` arm does).
const VETERANCY_PCT := [0, 10, 20, 35]

const DAMAGE_NAMES := {"Ballistic": "Ballistic", "AntiArmor": "Anti-armor", "Explosive": "Explosive"}
const ARMOUR_NAMES := {"Flesh": "Flesh", "Plated": "Plated", "Structure": "Structure"}


## The armour class of an entity of `kind` and snapshot `category` ("unit" or "building"): a unit kind from the table, any
## building Structure. "" when the pair is unknown, so no matchup is ever invented.
static func armour_of(kind: String, category: String) -> String:
	if category == "building":
		return "Structure"
	if category == "unit":
		return str(ARMOUR_OF.get(kind, ""))
	return ""


## The damage type of an armed unit kind, "" for a kind with no weapon.
static func damage_of(kind: String) -> String:
	return str(DAMAGE_OF.get(kind, ""))


## Damage change in percent of `damage` against `armour` (+50, -50, +75, 0).
static func multiplier_pct(damage: String, armour: String) -> int:
	for row in MATRIX:
		if row[0] == damage and row[1] == armour:
			return int(round(100.0 * float(row[2]) / float(row[3]))) - 100
	return 0


## Outgoing-damage bonus in percent for a veterancy rank.
static func veterancy_pct(rank: int) -> int:
	return int(VETERANCY_PCT[clampi(rank, 0, VETERANCY_PCT.size() - 1)])
