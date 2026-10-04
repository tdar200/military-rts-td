# Ascension: Earthfront to the Cosmic Frontier

Design and implementation blueprint • 3 October 2026 • proposal v1

**A real-time strategy campaign about earning new scales of agency through science, industry, and survival.** Humanity begins with an industrial foothold under alien attack. Every major breakthrough changes what the player can build, where they can operate, and which bottleneck matters next.

This package specifies the intended game. It does **not** claim that the cosmic campaign or the revised economy is implemented. The current repository is an Earthfront prototype with a deterministic simulation and experimental strategic systems. Existing gameplay files are unchanged by this design package.

Read in this order:

1. [Game and systems blueprint](BLUEPRINT.md) — vision, economy, warfare, research, all ten eras, scale, aliens, campaign, UI and architecture.
2. [Technology catalogue](TECHNOLOGIES.md) — 200 individually authored example technologies, with full records in [technologies.json](technologies.json).
3. [Playable implementation roadmap](ROADMAP.md) — repository audit, first-slice specification, migration sequence, acceptance tests and later milestones.
4. [Science boundary and sources](SCIENCE.md) — what is established, what is extrapolated, and where the game requires fictional physics.

The catalogue is **design data**, not a replacement for `tools/tech_grid_source.json` or the runtime 500-slot grid. Its costs are normalized balance seeds, not estimates of real-world scientific cost or completion dates. Research quantities, facility tags and unlocks require runtime bindings before shipping.

Validate the complete catalogue and regenerate its reader-friendly rendering:

```bash
python3 tools/ascension_catalog.py --check
python3 tools/ascension_catalog.py --render
```

The check rejects dangling dependencies, cycles, unreachable infrastructure, backwards-era requirements, missing science disclosures, inconsistent reverse links and invalid costs. It also checks the generated Markdown against the JSON. This is a content contract; it is not an RTS playtest.

## Decisions that hold the design together

- Fully visible battlefields; knowledge of alien capabilities is distinct from visibility.
- Scientific discovery, prototype validation and industrial deployment are separate achievements.
- Electricity is delivered power; stored energy is a different quantity.
- Logistics moves real inventory; industrial capacity is a rate, not spendable money.
- Old equipment retains economical roles; eras do not give every unit a global damage multiplier.
- Scale changes delegation and representation, not ownership or conservation rules.
- Lower-scale detail does not keep running millions of invisible agents.
- Faster-than-light travel and observable-universe control require an explicitly fictional ruleset. The grounded campaign has a complete endgame without them.
- Milestone 1 is one excellent Earth operation with two eras. The later catalogue is a plan, not launch scope.
