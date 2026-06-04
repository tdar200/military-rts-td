#!/usr/bin/env python3
"""Generate the 500-node Ascension tech-grid table (Rust) from the authored
workflow output. IDs are assigned by grid position (era*50+branch*5+step),
fixing the C/B/X slotting bugs; prereqs are a clean structural DAG; reality is
clamped so nothing past the frontier (era>4) is Achieved/Emerging."""
import json, re, sys

SRC = "tools/tech_grid_source.json"
OUT = "crates/core/src/game/tech_grid_table.rs"

REALITY = {"achieved":"Achieved","emerging":"Emerging","theoretical":"Theoretical",
           "speculative":"Speculative","lore":"Lore"}
FAMILIES = {"building":"Building","unit":"Unit","upgrade":"Upgrade","ability":"Ability",
            "system":"System","recipe":"Recipe","modifier":"Modifier"}

def esc(s): return s.replace("\\","\\\\").replace('"','\\"')

def parse_reality(s, era):
    key = re.split(r"[ /(]", s.strip().lower())[0]
    r = REALITY.get(key, "Theoretical")
    # Honesty rule: no Achieved/Emerging past the Frontier of Known Physics (era>4).
    if era > 4 and r in ("Achieved","Emerging"):
        r = "Theoretical"
    return r

def parse_unlocks(cell, node_name):
    out = []
    cell = cell.strip()
    if cell and cell not in ("—","-","–",""):
        for part in re.split(r"[;,]", cell):
            part = part.strip()
            if not part: continue
            if ":" in part:
                fam, name = part.split(":",1)
                fam = FAMILIES.get(fam.strip().lower())
                name = name.strip()
                if fam and name:
                    out.append((fam, name)); continue
            # malformed → treat as a named modifier
            out.append(("Modifier", part))
    if not out:
        # invariant: every node unlocks >=1 concrete item
        slug = re.sub(r"[^A-Za-z0-9]", "", node_name.title())[:40] or "Effect"
        out.append(("Modifier", slug))
    return out

def parse_mel(cell):
    m = re.findall(r"\d+", cell)
    if len(m) >= 3: return int(m[0]), int(m[1]), int(m[2])
    return 100, 50, 50

def main():
    d = json.load(open(SRC))
    blocks = sorted(d['branch_blocks'], key=lambda b: b["b"])
    nodes = {}  # id -> dict
    for blk in blocks:
        b = blk["b"]
        seen_ids = set()
        per_era = {}  # era -> list of rows (deduped, in order)
        for line in blk["md"].splitlines():
            line = line.strip()
            if not line.startswith("|"): continue
            cells = [c.strip() for c in line.strip("|").split("|")]
            if len(cells) < 7 or not re.match(r"^\d+$", cells[0]): continue
            aid = int(cells[0])
            if aid in seen_ids: continue   # branch P duplicated its table
            seen_ids.add(aid)
            era = int(cells[2])
            per_era.setdefault(era, []).append(cells)
        for era in range(10):
            rows = per_era.get(era, [])
            if len(rows) != 5:
                print(f"WARN branch {b} era {era}: {len(rows)} rows", file=sys.stderr)
            for step, cells in enumerate(rows[:5]):
                nid = era*50 + b*5 + step
                name = cells[1]
                reality = parse_reality(cells[4], era)
                # columns: id name era branch reality prereqs unlocks M/E/L dur stage tooltip
                unl = parse_unlocks(cells[6] if len(cells) > 6 else "", name)
                mel = parse_mel(cells[7] if len(cells) > 7 else "")
                dur = int(re.findall(r"\d+", cells[8])[0]) if len(cells) > 8 and re.findall(r"\d+", cells[8]) else 600
                nodes[nid] = dict(id=nid, name=name, era=era, branch=b, step=step,
                                  reality=reality, money=mel[0], energy=mel[1], labour=mel[2],
                                  dur=dur, unlocks=unl)
    assert len(nodes) == 500, f"expected 500 nodes, got {len(nodes)}"

    def prereqs(n):
        i, era, b, step = n["id"], n["era"], n["branch"], n["step"]
        if step > 0:
            return [i-1]
        if era == 0:
            return []
        ps = [i-46, (era-1)*50 + 9]   # prev-era same-branch capstone + prev era key
        # dedup (Energy branch step0: i-46 == prev era key)
        out = []
        for p in ps:
            if p not in out and p < i:
                out.append(p)
        return out

    lines = []
    lines.append("//! GENERATED — the 500-node Ascension tech-grid table.")
    lines.append("//!")
    lines.append("//! Authored by the `ascension-500-grid` workflow (10 branch arcs, validated),")
    lines.append("//! then mechanically transcribed: ids assigned by grid position")
    lines.append("//! (`era*50 + branch*5 + step`, fixing the authored slotting bugs), prereqs")
    lines.append("//! derived as a clean structural DAG (within-cell chain + per-era Energy spine),")
    lines.append("//! reality clamped so nothing past era 4 is Achieved/Emerging. Edit the")
    lines.append("//! generator, not this file. Dormant in M1 — not yet wired into gameplay.")
    lines.append("")
    lines.append("use super::tech_grid::{GridNode, RealityClass, Unlock, UnlockFamily, TECH_MAX};")
    lines.append("")
    lines.append("/// The full 500-slot capability grid, indexed by grid id.")
    lines.append("#[rustfmt::skip]")
    lines.append("pub static GRID: [GridNode; TECH_MAX] = [")
    for i in range(500):
        n = nodes[i]
        ps = prereqs(n)
        ps_s = "&[" + ", ".join(str(p) for p in ps) + "]"
        unl_s = "&[" + ", ".join(
            f'Unlock {{ family: UnlockFamily::{f}, name: "{esc(name)}" }}'
            for f, name in n["unlocks"]) + "]"
        lines.append(
            f'    GridNode {{ id: {i}, name: "{esc(n["name"])}", era: {n["era"]}, '
            f'branch: {n["branch"]}, step: {n["step"]}, reality: RealityClass::{n["reality"]}, '
            f'money: {n["money"]}, energy: {n["energy"]}, labour: {n["labour"]}, '
            f'duration: {n["dur"]}, prereqs: {ps_s}, unlocks: {unl_s} }},')
    lines.append("];")
    lines.append("")
    lines.append(TESTS)
    open(OUT, "w").write("\n".join(lines))
    print(f"wrote {OUT}: 500 nodes")

TESTS = r'''#[cfg(test)]
mod tests {
    use super::GRID;
    use crate::game::tech_grid::{
        branch_of, era_of, node, step_of, tech_id, RealityClass, ERA_KEYS, FRONTIER_AFTER_ERA,
        TECH_MAX,
    };

    #[test]
    fn grid_has_500_contiguous_well_formed_nodes() {
        assert_eq!(GRID.len(), TECH_MAX);
        for (i, n) in GRID.iter().enumerate() {
            let id = u32::try_from(i).unwrap();
            assert_eq!(n.id, id, "node at index {i} has id {}", n.id);
            assert_eq!(n.era, era_of(id));
            assert_eq!(n.branch, branch_of(id));
            assert_eq!(n.step, step_of(id));
            assert_eq!(tech_id(n.era, n.branch, n.step), id);
        }
    }

    #[test]
    fn every_node_unlocks_something_concrete() {
        for n in &GRID {
            assert!(!n.unlocks.is_empty(), "node {} ({}) has no unlock", n.id, n.name);
        }
    }

    #[test]
    fn prereqs_form_an_acyclic_dag_with_lower_ids() {
        for n in &GRID {
            for &p in n.prereqs {
                assert!(p < n.id, "node {} prereq {p} is not strictly lower", n.id);
                assert!(node(p).is_some(), "node {} prereq {p} out of range", n.id);
            }
            if n.era == 0 && n.step == 0 {
                assert!(n.prereqs.is_empty(), "era-0 root {} should have no prereq", n.id);
            } else {
                assert!(!n.prereqs.is_empty(), "non-root {} must have a prereq", n.id);
            }
        }
    }

    #[test]
    fn no_achieved_or_emerging_past_the_frontier() {
        for n in &GRID {
            if n.era > FRONTIER_AFTER_ERA {
                assert!(
                    !matches!(n.reality, RealityClass::Achieved | RealityClass::Emerging),
                    "node {} ({}) is {:?} past the frontier (era {})",
                    n.id, n.name, n.reality, n.era
                );
            }
        }
    }

    #[test]
    fn era_keys_are_reachable_energy_capstones() {
        for &key in &ERA_KEYS {
            let n = node(key).expect("era key exists");
            assert_eq!(n.branch, 1, "era key {key} must be Energy branch");
            assert_eq!(n.step, 4, "era key {key} must be the cell capstone");
        }
    }
}
'''

if __name__ == "__main__":
    main()
