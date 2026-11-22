#!/usr/bin/env python3
"""The night watchman. No LLM, so little can break. Run it daily from cron or launchd.

Reads $AGENT_OPS_DIR/runs.jsonl (written by claude-run and ops-check) and alerts when a loop:
- failed its last outcome check (or, with no check, its last Claude run didn't end in success)
- went silent: no run for twice its usual gap
- cost over 3x its median on the last run
Also runs bin/mission-guard check and alerts when a blessed charter's marked blocks drifted.
Writes COSTS.md, sends each alert at most every 3 days through $AGENT_OPS_NOTIFY (a command
called with a subject and a body; unset, it prints them), then logs its own pass line. If
$AGENT_OPS_DIR is a git repo with a remote, it commits and pushes, so a second watchman in the
cloud can check that line is fresh (examples/heartbeat-watch-prompt.md)."""
import datetime as dt, json, os, re, shlex, subprocess
from pathlib import Path

OPS = Path(os.environ.get("AGENT_OPS_DIR", Path.home() / ".agent-ops"))
LEDGER = OPS / "runs.jsonl"
now = dt.datetime.now()
alerts = {}

runs = []
for n, line in enumerate(LEDGER.read_text().splitlines() if LEDGER.exists() else [], 1):
    if not line.strip():
        continue
    try:
        r = json.loads(line)
        if not isinstance(r, dict) or not {"loop", "date"} <= r.keys():
            raise ValueError
        runs.append(r)
    except ValueError:
        alerts[f"ledger:{n}"] = f"runs.jsonl line {n} isn't a run, so it was skipped: {line[:100]}"
by_loop = {}
for r in runs:
    if r["loop"] != "heartbeat":
        by_loop.setdefault(r["loop"], []).append(r)
median = lambda xs: sorted(xs)[len(xs) // 2]

for loop, rs in by_loop.items():
    checks = [r for r in rs if "check" in r]
    claude = [r for r in rs if "check" not in r]
    if checks and checks[-1]["check"] != "pass":
        alerts[f"check:{loop}:{checks[-1]['date'][:10]}"] = f"{loop}: outcome check failed: {checks[-1].get('detail')}"
    elif not checks and claude[-1].get("subtype") != "success":
        last = claude[-1]
        alerts[f"run:{loop}:{last['date'][:10]}"] = f"{loop}: last run ended as {last.get('subtype')} (exit {last.get('exit')})."
    times = [dt.datetime.fromisoformat(r["date"]) for r in (checks or claude)]
    gaps = [(b - a).total_seconds() for a, b in zip(times, times[1:])]
    if len(gaps) >= 3 and (now - times[-1]).total_seconds() > 2 * median(gaps):
        alerts[f"silent:{loop}"] = f"{loop} hasn't run since {times[-1]:%d %b %H:%M}; it usually runs every {median(gaps) / 3600:.0f}h."
    costs = [r["cost"] for r in claude[:-1] if r.get("cost")]
    if len(costs) >= 5 and (claude[-1].get("cost") or 0) > 3 * median(costs):
        alerts[f"cost:{loop}:{claude[-1]['date'][:10]}"] = f"{loop}: last run cost ${claude[-1]['cost']:.2f}, over 3x its usual ${median(costs):.2f}."

guard = subprocess.run([str(Path(__file__).with_name("mission-guard")), "check"], capture_output=True, text=True)
if guard.returncode:
    drifts = re.split(r"\n(?=\S)", guard.stdout.strip())[:-1] or [(guard.stderr or guard.stdout).strip()[-500:]]
    for d in drifts:
        alerts[f"mission:{d.split(':', 1)[0]}"] = "A charter's mission blocks changed without your bless. Revert it, or bless it if it was you:\n" + d

since = lambda days: (now - dt.timedelta(days=days)).isoformat()
cost = lambda rs, days: sum(r.get("cost") or 0 for r in rs if "check" not in r and r["date"] >= since(days))
failed = lambda r: r.get("check") == "fail" or ("check" not in r and r.get("subtype") != "success")
rows = ["| loop | runs 7d | failed 7d | cost 7d | cost 30d | last run |", "|---|---|---|---|---|---|"]
for loop, rs in sorted(by_loop.items(), key=lambda kv: -cost(kv[1], 30)):
    week = [r for r in rs if r["date"] >= since(7)]
    rows.append(f"| {loop} | {len(week)} | {sum(map(failed, week))} | ${cost(rs, 7):.2f} | ${cost(rs, 30):.2f} | {rs[-1]['date'][:16]} |")
OPS.mkdir(parents=True, exist_ok=True)
(OPS / "COSTS.md").write_text(f"# Loop runs and cost\n\nUpdated {now:%Y-%m-%d %H:%M} by heartbeat.py. Cost is Claude's API-equivalent estimate; paid APIs a loop calls are not in it.\n\n" + "\n".join(rows) + "\n")

state_file = OPS / "alerts.json"
state = json.loads(state_file.read_text()) if state_file.exists() else {}
due = {k: v for k, v in alerts.items() if k not in state or now - dt.datetime.fromisoformat(state[k]) > dt.timedelta(days=3)}
if due:
    subject, body = f"{len(due)} loop alert(s)", "\n\n".join(due.values())
    notify = os.environ.get("AGENT_OPS_NOTIFY")
    if subprocess.run([*shlex.split(notify), subject, body] if notify else ["printf", "%s\n\n%s\n", subject, body]).returncode == 0:
        state.update({k: now.isoformat() for k in due})
state_file.write_text(json.dumps({k: v for k, v in state.items() if k in alerts}))  # resolved alerts can fire again

with LEDGER.open("a") as f:
    f.write(json.dumps({"loop": "heartbeat", "date": now.isoformat(timespec="seconds"), "check": "pass", "detail": f"{len(alerts)} alert(s)"}) + "\n")
if (OPS / ".git").exists():
    subprocess.run(f"git add -A && git commit -qm 'heartbeat {now:%F}'; git pull -q --rebase && git push -q", shell=True, cwd=OPS)
print(json.dumps({"alerts": list(alerts), "sent": list(due)}))
