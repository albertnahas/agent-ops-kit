#!/usr/bin/env python3
"""Outcome check for the {{name}} loop, written by new-loop before its first run. No model, free.
Passes only when today's report landed on origin with every section, and, once the Floor is measured,
the Good block's number, read from its Source and never from anything the loop writes, is on the right
side of the Floor. Run it through ops-check so the result lands in the ledger:
  ops-check -l {{name}} -- python3 <this file> [YYYY-MM-DD]"""
import datetime as dt, re, subprocess, sys

REPO = {{repo}}
REPORT = {{report}}  # with {day} for the date
FLOOR = {{floor}}
MEASURE = {{measure}}  # a shell command, run in REPO, whose last line is the number the Floor is about
SECTIONS = ("TLDR", "KPIs", "Findings", "Actions taken", "Escalations", "Handoff")

git = lambda *a: subprocess.run(["git", "-C", REPO, *a], capture_output=True, text=True)
day = sys.argv[1] if len(sys.argv) > 1 else dt.date.today().isoformat()
fails = []

if git("fetch", "-q", "--prune", "origin").returncode:
    sys.exit("can't fetch origin")
path = REPORT.format(day=day)
refs = git("for-each-ref", "--sort=-committerdate", "--format=%(refname:short)", "refs/remotes/origin").stdout.split()
found = next(((r, s.stdout) for r in refs for s in [git("show", f"{r}:{path}")] if s.returncode == 0), None)
if not found:
    fails.append(f"no {path} on any branch of origin")
else:
    heads = [re.sub(r"^(#+|\d+\.)\s*(\*\*)?(\d+\.\s*)?", "", l).lower() for l in found[1].splitlines() if re.match(r"(#+|\d+\.) ", l)]
    missing = [s for s in SECTIONS if not any(h.startswith(s.lower()) for h in heads)]
    print(f"{path} on {found[0]}" + (f" lacks: {', '.join(missing)}" if missing else ""))
    fails += [f"report lacks {s}" for s in missing]

level = re.match(r"(at least|at most)\s+([\d,]*\.?\d+)", FLOOR, re.I)
if level:
    out = subprocess.run(MEASURE, shell=True, cwd=REPO, capture_output=True, text=True)
    last = (out.stdout.strip().splitlines() or [""])[-1].replace(",", "")
    if out.returncode or not re.fullmatch(r"-?\d*\.?\d+", last):
        fails.append(f"the measure gave no number (exit {out.returncode}): {(out.stderr or out.stdout).strip()[-200:]}")
    else:
        way, have, want = level.group(1).lower(), float(last), float(level.group(2).replace(",", ""))
        print(f"measured {last}, Floor {way} {level.group(2)}")
        if have < want if way == "at least" else have > want:
            fails.append(f"{last} is not {way} the Floor of {level.group(2)}")
else:
    print(f"Floor {FLOOR}: only the report is checked until it's measured")

print("; ".join(fails) or "pass")
sys.exit(bool(fails))
