#!/usr/bin/env python3
"""The night watchman. No LLM, so little can break. Run it daily from cron or launchd.

Reads $AGENT_OPS_DIR/runs.jsonl (written by claude-run and ops-check) and alerts when a loop:
- failed its last outcome check (or, with no check, its last Claude run crashed: not success, a non-zero exit, or is_error)
- went silent: no run for twice its usual gap
- cost over 3x its median on the last run
Runs logged as adhoc (claude-run or ops-check with no loop name) are no loop: they count in COSTS.md and never alert.
Also runs bin/mission-guard check and alerts when a blessed charter's marked blocks drifted.
Writes COSTS.md, sends each alert at most every 3 days through $AGENT_OPS_NOTIFY (a command
called with a subject and a body; unset, it prints them), then logs its own line: pass, or fail
when the notifier failed. If $AGENT_OPS_DIR is itself a git repo with a remote, it commits
runs.jsonl, COSTS.md and what hooks name, nothing else, and pushes (runs.jsonl merges as a union, so two writers
never conflict), so a second watchman in the cloud can check that line is fresh
(examples/heartbeat-watch-prompt.md); a failed sync logs a fail line and leaves local edits as they were.
The sync holds .git/ops-git.lock (flock), waiting up to 3 minutes for whoever has it.
A ledger line that isn't a run (no loop name, a date that isn't one or is in the future, bytes that aren't
UTF-8) is skipped with an alert, never a crash.

Hooks: each executable in $AGENT_OPS_DIR/heartbeat.d runs in name order after the built-in checks, with
{"alerts": {key: message}, "runs": [...]} on stdin, and prints {"alerts": {...}, "commit": [paths]}: the alerts
from here on (so a hook can add, replace or drop them) and any files it wrote that the sync should commit. A hook
that fails or prints anything else leaves the alerts as they were and adds one of its own. The notifier also gets
the due alerts as JSON on stdin, so a router can send each to its own place by key."""
import datetime as dt, fcntl, json, os, re, shlex, subprocess, time
from pathlib import Path

OPS = Path(os.environ.get("AGENT_OPS_DIR", Path.home() / ".agent-ops"))
LEDGER = OPS / "runs.jsonl"
now = dt.datetime.now()
alerts = {}

def when(date):
    """A ledger date as local time without a zone, so writers with and without offsets compare; None if it isn't one.
    Z, ±HHMM and any fraction are rewritten first: Python 3.9, the macOS system python, reads only ±HH:MM and 3 or 6 digits."""
    try:
        date = re.sub(r"Z$|([+-]\d\d):?(\d\d)$", lambda m: f"{m[1]}:{m[2]}" if m[1] else "+00:00", date)
        t = dt.datetime.fromisoformat(re.sub(r"\.(\d+)", lambda m: "." + m[1][:6].ljust(6, "0"), date))
    except (TypeError, ValueError): return None
    return t.astimezone().replace(tzinfo=None) if t.tzinfo else t

runs = []
text = LEDGER.read_bytes().decode(errors="replace").replace("\0", "") if LEDGER.exists() else ""
for n, line in enumerate(text.splitlines(), 1):
    if not line.strip():
        continue
    try: r = json.loads(line)
    except ValueError: r = None
    t = isinstance(r, dict) and when(r.get("date"))
    if not (t and isinstance(r.get("loop"), str) and r["loop"] and t <= now + dt.timedelta(minutes=5)):
        alerts[f"ledger:{n}"] = f"runs.jsonl line {n} isn't a run (a loop, and a date that isn't in the future), so it was skipped: {line[:100]}"
        continue
    if not isinstance(r.get("cost"), (int, float)): r.pop("cost", None)
    runs.append({**r, "at": t})
runs.sort(key=lambda r: r["at"])  # the latest run is the last one, whatever order the lines were appended in
by_loop = {}
for r in runs:
    if r["loop"] != "heartbeat":
        by_loop.setdefault(r["loop"], []).append(r)
median = lambda xs: sorted(xs)[len(xs) // 2]
crashed = lambda r: r.get("subtype") != "success" or bool(r.get("exit") or r.get("is_error"))  # a crash can still say success

for loop, rs in by_loop.items():
    if loop == "adhoc": continue
    checks = [r for r in rs if "check" in r]
    claude = [r for r in rs if "check" not in r]
    if checks and checks[-1]["check"] != "pass":
        alerts[f"check:{loop}"] = f"{loop}: outcome check failed: {checks[-1].get('detail')}"
    elif not checks and crashed(claude[-1]):
        last = claude[-1]
        alerts[f"run:{loop}"] = f"{loop}: last run ended as {last.get('subtype')} (exit {last.get('exit')})."
    times = [r["at"] for r in (checks or claude)]
    gaps = [g for g in ((b - a).total_seconds() for a, b in zip(times, times[1:])) if g >= 60]  # repeats aren't a schedule
    if len(gaps) >= 3 and (now - times[-1]).total_seconds() > 2 * median(gaps):
        alerts[f"silent:{loop}"] = f"{loop} hasn't run since {times[-1]:%d %b %H:%M}; it usually runs every {median(gaps) / 3600:.0f}h."
    costs = [r["cost"] for r in claude[:-1] if r.get("cost")]
    if len(costs) >= 5 and (claude[-1].get("cost") or 0) > 3 * median(costs):
        alerts[f"cost:{loop}"] = f"{loop}: last run cost ${claude[-1]['cost']:.2f}, over 3x its usual ${median(costs):.2f}."

guard = subprocess.run([str(Path(__file__).with_name("mission-guard")), "check"], capture_output=True, text=True)
for item in re.split(r"\n(?=\S)", guard.stdout.strip()):
    kind, _, rest = item.partition(": ")
    if kind == "drift":
        alerts[f"mission:{rest.split(':', 1)[0]}"] = "A charter's mission blocks changed without your bless. Revert it, or bless it if it was you:\n" + rest
    elif kind == "unreadable":
        alerts[f"mission-unreadable:{rest.split(':', 1)[0]}"] = "mission-guard couldn't read a charter, so it isn't guarded right now: " + rest
if guard.returncode and not re.search(r"^(drift|unreadable): ", guard.stdout, re.M):
    alerts["mission-guard"] = "mission-guard failed, so no charter is guarded right now: " + (guard.stderr or guard.stdout).strip()[-400:]

def hook(path):
    """A hook's alerts and files to commit, or None and why it failed."""
    context = json.dumps({"alerts": alerts, "runs": [{**r, "at": f"{r['at']:%FT%T}"} for r in runs]})
    try: out = subprocess.run([str(path)], input=context, capture_output=True, text=True, errors="replace", timeout=900, env={**os.environ, "AGENT_OPS_DIR": str(OPS)})
    except (OSError, subprocess.TimeoutExpired) as e: return None, str(e)[:300]
    try:
        res = json.loads(out.stdout); files = res.get("commit", [])
        if not out.returncode and all(isinstance(k, str) and isinstance(v, str) for k, v in res["alerts"].items()) and isinstance(files, list) and all(isinstance(f, str) for f in files):
            return (res["alerts"], files), None
    except (ValueError, TypeError, KeyError, AttributeError): pass
    return None, f"exited {out.returncode}: {(out.stderr or out.stdout).strip()[-300:]}"

commit = [LEDGER.name, "COSTS.md"]
for path in sorted(p for p in (OPS / "heartbeat.d").glob("*") if p.is_file() and os.access(p, os.X_OK)):
    res, why = hook(path)
    if res: alerts, commit = res[0], commit + res[1]
    else: alerts[f"hook:{path.name}"] = f"The heartbeat hook {path.name} failed, so its checks didn't run: {why}"

since = lambda days: now - dt.timedelta(days=days)
cost = lambda rs, days: sum(r.get("cost") or 0 for r in rs if "check" not in r and r["at"] >= since(days))
failed = lambda r: r.get("check") == "fail" or ("check" not in r and crashed(r))
rows = ["| loop | runs 7d | failed 7d | denied calls 7d | cost 7d | cost 30d | last run |", "|---|---|---|---|---|---|---|"]
for loop, rs in sorted(by_loop.items(), key=lambda kv: -cost(kv[1], 30)):
    week = [r for r in rs if r["at"] >= since(7)]
    rows.append(f"| {loop} | {len(week)} | {sum(map(failed, week))} | {sum(r.get('denials') or 0 for r in week)} | ${cost(rs, 7):.2f} | ${cost(rs, 30):.2f} | {rs[-1]['at']:%Y-%m-%dT%H:%M} |")
OPS.mkdir(parents=True, exist_ok=True)
(OPS / "COSTS.md").write_text(f"# Loop runs and cost\n\nUpdated {now:%Y-%m-%d %H:%M} by heartbeat.py. Cost is Claude's API-equivalent estimate; paid APIs a loop calls are not in it.\n\n" + "\n".join(rows) + "\n")

state_file = OPS / "alerts.json"
state = json.loads(state_file.read_text()) if state_file.exists() else {}
due = {k: v for k, v in alerts.items() if k not in state or now - dt.datetime.fromisoformat(state[k]) > dt.timedelta(days=3)}
undelivered = None
if due:
    subject, body = f"{len(due)} loop alert(s)", "\n\n".join(due.values())
    notify = os.environ.get("AGENT_OPS_NOTIFY")
    try:
        sent = subprocess.run([*shlex.split(notify), subject, body] if notify else ["printf", "%s\n\n%s\n", subject, body], input=json.dumps(due), stderr=subprocess.PIPE, text=True)
        undelivered = sent.returncode and f"the notifier exited {sent.returncode}: {sent.stderr.strip()[-200:]}"
    except (OSError, ValueError) as e:  # a notifier that won't start, or AGENT_OPS_NOTIFY that won't parse
        undelivered = f"the notifier didn't start: {e}"
    if not undelivered:
        state.update({k: now.isoformat() for k in due})
state_file.write_text(json.dumps({k: v for k, v in state.items() if k in alerts}))  # resolved alerts can fire again

def log(check, detail):
    lead = "\n" if LEDGER.exists() and not LEDGER.read_bytes().endswith(b"\n") and LEDGER.stat().st_size else ""
    with LEDGER.open("a") as f:
        f.write(lead + json.dumps({"loop": "heartbeat", "date": now.isoformat(timespec="seconds"), "check": check, "detail": detail}) + "\n")

log("fail" if undelivered else "pass", f"{len(alerts)} alert(s)" + (f", none delivered: {undelivered}" if undelivered else ""))
git = lambda *a: subprocess.run(["git", *a], cwd=OPS, capture_output=True, text=True)
if git("rev-parse", "--show-toplevel").stdout.strip() == str(OPS.resolve()) and git("remote").stdout.strip():  # never a parent repo
    attrs = OPS / git("rev-parse", "--git-path", "info/attributes").stdout.strip()  # read during a rebase too, unlike .gitattributes
    if "runs.jsonl merge=union" not in (attrs.read_text() if attrs.exists() else ""):
        attrs.parent.mkdir(exist_ok=True)
        with attrs.open("a") as f: f.write("runs.jsonl merge=union\n")
    lock = (OPS / git("rev-parse", "--git-path", "ops-git.lock").stdout.strip()).open("a")  # the lock any other script syncing this repo takes
    for _ in range(180):
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB); break
        except BlockingIOError: time.sleep(1)
    git("add", "--", *[c for c in commit if (OPS / c).exists()])  # a missing path would stage nothing
    git("commit", "-qm", f"heartbeat {now:%F}")  # only these: other edits stay local
    head, sync = git("rev-parse", "HEAD").stdout.strip(), git("pull", "-q", "--rebase", "--autostash")
    clash = not sync.returncode and git("ls-files", "-u").stdout  # the pull went through, but local edits clash with it
    if clash: git("reset", "-q", "--hard", head); git("stash", "pop", "-q")  # so put the tree back as it was
    elif sync.returncode: git("rebase", "--abort")
    else: sync = git("push", "-q")
    if clash: log("fail", "the ops repo didn't sync: local edits clash with the remote, so they were left as they were")
    elif sync.returncode: log("fail", "the ops repo didn't sync: " + next((l for l in sync.stderr.splitlines() if l.startswith(("fatal:", "error:"))), sync.stderr.strip()[-200:])[:200])
print(json.dumps({"alerts": list(alerts), "sent": [] if undelivered else list(due)}))
