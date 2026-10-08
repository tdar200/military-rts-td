#!/usr/bin/env python3
"""Structure check for a GitHub Actions workflow, used when `actionlint` is absent.

usage: check_ci_yaml.py <workflow.yml>

Exits 0 when the YAML parses, there is at least one job, every job has `runs-on`
and a non-empty `steps` list, and every step has `run` or `uses`. Otherwise it
prints each problem to stderr and exits 1 (2 for a usage or read error).
This is a local sanity check, not a schema validator: the workflows cannot run
on GitHub from this repository (there is no remote).
"""
import sys

import yaml


def problems(doc):
    if not isinstance(doc, dict):
        return ["the file is not a YAML mapping"]
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        return ["`jobs` is missing or empty"]
    found = []
    for name, job in jobs.items():
        if not isinstance(job, dict):
            found.append(f"job {name}: not a mapping")
            continue
        if "runs-on" not in job:
            found.append(f"job {name}: no `runs-on`")
        steps = job.get("steps")
        if not isinstance(steps, list) or not steps:
            found.append(f"job {name}: `steps` is missing or empty")
            continue
        for i, step in enumerate(steps, 1):
            if not isinstance(step, dict) or not ("run" in step or "uses" in step):
                label = step.get("name", "unnamed") if isinstance(step, dict) else "not a mapping"
                found.append(f"job {name}: step {i} ({label}) has neither `run` nor `uses`")
    return found


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            doc = yaml.safe_load(handle)
    except (OSError, yaml.YAMLError) as err:
        print(f"{argv[1]}: {err}", file=sys.stderr)
        return 2
    found = problems(doc)
    for line in found:
        print(f"{argv[1]}: {line}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
