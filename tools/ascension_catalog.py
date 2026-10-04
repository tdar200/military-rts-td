#!/usr/bin/env python3
"""Validate and render the design-only Ascension catalogue; no game-state writes."""
import argparse
from collections import Counter
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/ascension/technologies.json'
OUTPUT = ROOT / 'docs/ascension/TECHNOLOGIES.md'
RATINGS = {'Established', 'Experimental', 'Theoretically plausible',
           'Highly speculative', 'Unknown physics required'}


def validate(data):
    """Return actionable errors, including graph and facility reachability failures."""
    errors = []
    nodes = data.get('technologies', [])
    if data.get('schema_version') != 1:
        errors.append('Unsupported schema_version')
    if len(nodes) != 200:
        errors.append(f'Expected 200 technologies, found {len(nodes)}')
    ids = [n.get('id') for n in nodes]
    if len(set(ids)) != len(ids):
        errors.append('Duplicate technology IDs')
    registry = {n.get('id'): n for n in nodes}
    counts = Counter(n.get('era') for n in nodes)
    if counts != Counter({i: 20 for i in range(1, 11)}):
        errors.append(f'Expected 20 entries per era, found {dict(counts)}')
    if len({n.get('name') for n in nodes}) != len(nodes):
        errors.append('Duplicate technology names')
    starting = set(data.get('starting_infrastructure', []))
    providers = {}
    for n in nodes:
        for capability in n.get('provides_infrastructure', []):
            if capability in providers or capability in starting:
                errors.append(f'{n["id"]}: duplicate infrastructure provider {capability}')
            providers[capability] = n['id']
            if not n.get('buildings_unlocked'):
                errors.append(f'{n["id"]}: infrastructure provider has no building')
    required = ('id', 'name', 'era', 'scientific_field', 'description', 'prerequisites',
                'research_requirements', 'infrastructure_requirement', 'economic_cost',
                'energy_requirement', 'gameplay_effect', 'units_unlocked',
                'buildings_unlocked', 'technologies_enabled', 'scientific_plausibility',
                'science', 'ruleset', 'implementation_status', 'deployment_requirement')
    references = data.get('references', {})
    for n in nodes:
        ident = n.get('id', '<missing ID>')
        for key in required:
            if key not in n or n[key] is None:
                errors.append(f'{ident}: missing {key}')
        for key in ('name', 'scientific_field', 'description', 'gameplay_effect', 'deployment_requirement'):
            if not isinstance(n.get(key), str) or not n[key].strip():
                errors.append(f'{ident}: empty text {key}')
        if n.get('scientific_plausibility') not in RATINGS:
            errors.append(f'{ident}: invalid plausibility')
        if n.get('ruleset') not in ('both', 'speculative_frontier'):
            errors.append(f'{ident}: invalid ruleset')
        if n.get('implementation_status') != 'design_only':
            errors.append(f'{ident}: catalogue must not claim runtime implementation')
        deps = n.get('prerequisites', [])
        if len(set(deps)) != len(deps):
            errors.append(f'{ident}: duplicate prerequisites')
        for dep in deps:
            if dep not in registry:
                errors.append(f'{ident}: missing prerequisite {dep}')
            elif registry[dep].get('era', 99) > n.get('era', 0):
                errors.append(f'{ident}: future-era prerequisite {dep}')
            elif n.get('ruleset') == 'both' and registry[dep].get('ruleset') != 'both':
                errors.append(f'{ident}: causal route requires speculative-only {dep}')
        science = n.get('science', {})
        for key in ('inspiration', 'required_assumptions', 'physics_status'):
            if not isinstance(science.get(key), str) or not science[key].strip():
                errors.append(f'{ident}: missing science disclosure {key}')
        for ref in science.get('reference_ids', []):
            if ref not in references:
                errors.append(f'{ident}: unknown science reference {ref}')
        if n.get('scientific_plausibility') == 'Unknown physics required' and n.get('ruleset') != 'speculative_frontier':
            errors.append(f'{ident}: unknown physics must be opt-in')
        research = n.get('research_requirements', {})
        cost = n.get('economic_cost', {})
        energy = n.get('energy_requirement', {})
        positive = [(key, research.get(key)) for key in ('theory_work', 'experimental_work',
                    'qualified_specialist_capacity', 'compute_service', 'max_parallel_experiments')]
        positive += [('prototype_industrial_work', cost.get('prototype_industrial_work')),
                     ('delivered_power', energy.get('delivered_power'))]
        positive += list(cost.get('materials', {}).items())
        if not cost.get('materials'):
            errors.append(f'{ident}: empty material bill')
        for key, value in positive:
            if type(value) is not int or value <= 0:
                errors.append(f'{ident}: {key} must be a positive integer')
        threshold = energy.get('minimum_operating_fraction_per_mille', 0)
        if type(threshold) is not int or not 0 < threshold <= 1000:
            errors.append(f'{ident}: invalid power threshold')
        if energy.get('power_unit') not in ('kW', 'MW', 'GW', 'TW', 'PW', 'stellar_power_unit'):
            errors.append(f'{ident}: unrecognized power unit')
        for item in research.get('required_evidence', []):
            if not item.get('source') or not item.get('kind') or type(item.get('quantity')) is not int or item['quantity'] <= 0:
                errors.append(f'{ident}: incomplete evidence requirement')
        for item in research.get('alternative_evidence', []):
            if not item.get('kind') or type(item.get('quantity')) is not int or item['quantity'] <= 0:
                errors.append(f'{ident}: incomplete alternative evidence')
        for capability in n.get('infrastructure_requirement', []):
            if capability not in starting and capability not in providers:
                errors.append(f'{ident}: missing facility provider {capability}')
    # DFS returns strict ancestors, so a technology cannot commission its own lab.
    visiting, ancestors = set(), {}

    def walk(ident):
        if ident in ancestors:
            return ancestors[ident]
        if ident in visiting:
            errors.append(f'Cycle detected at {ident}')
            return set()
        visiting.add(ident)
        found = set()
        for dep in registry[ident].get('prerequisites', []):
            if dep in registry:
                found.add(dep)
                found.update(walk(dep))
        visiting.remove(ident)
        ancestors[ident] = found
        return found

    for ident in registry:
        walk(ident)
    for ident, n in registry.items():
        for capability in n.get('infrastructure_requirement', []):
            provider = providers.get(capability)
            if provider and provider not in ancestors[ident]:
                errors.append(f'{ident}: facility {capability} is not unlocked by an ancestor')
        expected = sorted(other['id'] for other in nodes if ident in other.get('prerequisites', []))
        if sorted(n.get('technologies_enabled', [])) != expected:
            errors.append(f'{ident}: technologies_enabled does not match reverse dependencies')
    return errors


def render(data):
    out = ['# Ascension: 200 technology examples', '',
           'Generated from [technologies.json](technologies.json). Edit JSON, then run '
           '`python3 tools/ascension_catalog.py --render`.', '',
           '**Design-only catalogue.** Twenty technologies per era. These are not 200 implemented unlocks. '
           'All costs are initial normalized balance seeds; commissioning and production remain separate.', '',
           'Starting knowledge: ' + ', '.join(data['starting_knowledge']) + '.', '',
           'Every project requires a built, powered research campus or the named successor facility. '
           'Facilities below are requirements, not automatically created by completing prerequisites. '
           'Work, specialists and compute use era-local normalized capacity units. '
           'The minimum powered fraction is a hard operating threshold; progress above it scales with delivered service. '
           'Energy expenditure integrates actual delivered power over runtime. One stellar power unit means 10²⁶ W for display.', '',
           'Required evidence is AND; alternative evidence is an OR clause in addition to required evidence. '
           'A prototype validation is mandatory before deployment. Prerequisites shown include facility-enabling discoveries.', '',
           'Each project then requires compatible factory tooling, materials and logistics; unlocks are designs, not spawned units. '
           'Plausibility applies to the whole proposed capability. See [science boundaries](SCIENCE.md).', '']
    reg = {t['id']: t for t in data['technologies']}
    era = 0
    for t in data['technologies']:
        if t['era'] != era:
            era = t['era']
            out += [f'## Era {era} — {data["eras"][era-1]["name"]}', '']
        r, c, e = t['research_requirements'], t['economic_cost'], t['energy_requirement']
        facilities=[]
        for f in t['infrastructure_requirement']:
            facilities.append('Starting research campus' if f == 'starting_research_campus'
                              else reg[f.split(':')[1]]['buildings_unlocked'][0] + ' (' + f.split(':')[1] + ')')
        evidence = ', '.join(f'{x["quantity"]} {x["kind"]}: {x["source"]}' for x in r['required_evidence']) or 'No unique sample required'
        if r['alternative_evidence']:
            evidence += '; plus one of: ' + ' OR '.join(f'{x["quantity"]} {x["kind"]}' for x in r['alternative_evidence'])
        out += [f'### {t["id"]} — {t["name"]}', '', t['description'], '',
                f'- **Field / plausibility:** {t["scientific_field"]}; {t["scientific_plausibility"]}. Ruleset: {t["ruleset"]}.',
                '- **Prerequisites:** ' + (', '.join(t['prerequisites']) or 'Starting knowledge') + '.',
                f'- **Research:** {r["theory_work"]} theory work + {r["experimental_work"]} experimental work; '
                f'{r["qualified_specialist_capacity"]} specialist capacity, {r["compute_service"]} compute service; '
                f'at most {r["max_parallel_experiments"]} parallel experiments. {evidence}.',
                '- **Infrastructure:** ' + ', '.join(facilities) + '.',
                '- **Economic cost:** ' + ', '.join(f'{v} {k}' for k,v in c['materials'].items()) +
                f'; {c["prototype_industrial_work"]} prototype industrial work.',
                f'- **Power:** {e["delivered_power"]} {e["power_unit"]} requested; minimum '
                f'{e["minimum_operating_fraction_per_mille"] / 10:g}% delivered to operate.',
                '- **Gameplay effect / prototype test:** ' + t['gameplay_effect'],
                '- **Units unlocked:** ' + (', '.join(t['units_unlocked']) or 'None; systemic capability') + '.',
                '- **Buildings unlocked:** ' + (', '.join(t['buildings_unlocked']) or 'None; upgrade or doctrine') + '.',
                '- **Technologies enabled:** ' + (', '.join(t['technologies_enabled']) or 'Terminal capability / campaign objective') + '.',
                '- **Science:** ' + t['science']['inspiration'] + '. Assumption: ' + t['science']['required_assumptions'] +
                '. Status: ' + t['science']['physics_status']]
        if t['science']['reference_ids']:
            out.append('- **Science boundary references:** ' + ', '.join(
                f'[{key}]({data["references"][key]})' for key in t['science']['reference_ids']) + '.')
        out += ['']
    return '\n'.join(out) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Validate JSON and check the Markdown is current')
    parser.add_argument('--render', action='store_true', help='Validate JSON, then regenerate Markdown')
    args = parser.parse_args()
    if not args.check and not args.render:
        parser.error('choose --check or --render')
    try:
        data = json.loads(SOURCE.read_text())
        errors = validate(data)
        if errors:
            for error in errors:
                print(error, file=sys.stderr)
            return 1
        result = render(data)
        if args.render:
            OUTPUT.write_text(result)
        if args.check and (not OUTPUT.exists() or OUTPUT.read_text() != result):
            print('TECHNOLOGIES.md is stale; run --render', file=sys.stderr)
            return 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'Invalid catalogue: {error}', file=sys.stderr)
        return 1
    print('PASS: 200 technologies; 10 eras; acyclic dependencies; reachable facilities; '
          'causal ruleset isolation; science disclosures; costs; reverse links; Markdown current.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
