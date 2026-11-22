#!/usr/bin/env python3
"""Fleet builder, no model. Reads $AGENT_OPS_DIR/fleet.json and writes <out>/loops.json (every scheduled loop, service and
one-off job with its health), <out>/waiting.json (everything waiting on you) and <out>/dashboard.html (both, drawn).
Sources: the registry file, launchd plists, your crontab, the run ledger, <out>/cloud.json (Claude routines and
desktop tasks, written by the claude.ai sync in fleet/SYNC.md), and optionally a queue file, GitHub PRs and decision memos.
fleet/README.md says how each status is decided."""
import datetime as dt, json, os, plistlib, re, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OPS = Path(os.environ.get("AGENT_OPS_DIR", Path.home() / ".agent-ops")).expanduser()
CONFIG = Path(os.environ.get("FLEET_CONFIG", OPS / "fleet.json")).expanduser()
WINDOW = 30  # days for pass rate and cost
STALE_SNAPSHOT_H = 36

def load_config():
    cfg = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    home = Path(cfg.get("home", OPS)).expanduser()
    path = lambda key, default: Path(cfg.get(key, home / default)).expanduser()
    return {**cfg, "home": home, "registry": path("registry", "REGISTRY.md"), "ledger": path("ledger", "runs.jsonl"),
            "checks": path("checks", "checks"), "out": path("out", "fleet"),
            "launch_agents": path("launch_agents", Path.home() / "Library/LaunchAgents"),
            "refresh": cfg.get("refresh", "Rebuilt by fleet.py"), "waiting": cfg.get("waiting", {})}

C = load_config()
GH = shutil.which("gh") or next((p for p in ("/opt/homebrew/bin/gh", "/usr/local/bin/gh") if Path(p).exists()), None)

def failed(r):
    """A Claude run that failed. A crash still says subtype success; exit and is_error are the truth."""
    return bool(r.get("subtype") != "success" or r.get("exit") or r.get("is_error"))

norm = lambda s: re.sub(r"[^a-z0-9]", "", (s or "").lower())

def scoping(registry):
    """name -> (the registry project it names, ignoring case and punctuation, or "", its scope). The scope is that
    project, or General: no project, a project listed under `general` in fleet.json, or nothing a registry row owns."""
    projects = {norm(r["Project"]): r["Project"] for r in registry if r.get("Project")}
    general = {norm(g) for g in C.get("general", [])}
    def of(name):
        p = projects.get(norm(name), "")
        return p, p if p and norm(p) not in general else "General"
    return of

def table(md, heading):
    """Rows of the first markdown table under `## heading`, as dicts keyed by header; [] if there is none."""
    if f"## {heading}" not in md: return []
    sec = md.split(f"## {heading}", 1)[1].split("\n## ", 1)[0]
    lines = [l for l in sec.splitlines() if l.startswith("|")]
    if len(lines) < 2: return []
    cells = lambda l: [c.strip() for c in l.strip().strip("|").split("|")]
    head = cells(lines[0])
    return [dict(zip(head, cells(l))) for l in lines[2:]]

# --- schedules: launchd calendar dicts and crons share one form, {Minute, Hour, Day, Month, Weekday} -> sets

NAMES = {n: i for i, n in enumerate(["sun", "mon", "tue", "wed", "thu", "fri", "sat"])} | \
        {n: i + 1 for i, n in enumerate(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"])}

def cron_spec(expr, both=False):
    """Cron's rule: with both day of month and weekday restricted, either one matching fires. both=True makes it
    both, for registry overrides that describe what a runner really does ("first Monday": `0 8 1-7 * 1`)."""
    expr = re.sub(r"^CRON_TZ=\S+\s+", "", expr.strip())
    num = lambda s: NAMES[s.lower()[:3]] if s[:1].isalpha() else int(s)
    def field(f, lo, hi):
        if f == "*": return None
        out = set()
        for part in f.split(","):
            rng, _, step = part.partition("/")
            a, _, b = rng.partition("-")
            a, b = (lo, hi) if a == "*" else (num(a), num(b) if b else (hi if step else num(a)))
            if b < a and hi == 7: b += 7  # weekdays wrap: sat-sun
            out |= set(range(a, b + 1, int(step or 1)))
        return out
    m, h, d, mo, wd = expr.split()[:5]
    return [{"Minute": field(m, 0, 59), "Hour": field(h, 0, 23), "Day": field(d, 1, 31),
             "Month": field(mo, 1, 12), "Weekday": {w % 7 for w in field(wd, 0, 7)} if wd != "*" else None,
             "either": not both and d != "*" and wd != "*"}]

def plist_spec(cal):
    return [{k: ({c[k] % 7} if k == "Weekday" else {c[k]}) if k in c else None
             for k in ("Minute", "Hour", "Day", "Month", "Weekday")} for c in (cal if isinstance(cal, list) else [cal])]

def fires(spec, start, direction, days=70):
    """Scheduled times after (direction 1) or before (-1) start, nearest first. Day and Weekday must both match,
    unless the spec says either (a crontab line restricting both). A missing Minute or Hour is every one."""
    day = start.replace(hour=0, minute=0, second=0, microsecond=0)
    for i in range(days):
        d = day + dt.timedelta(days=i * direction)
        ts = sorted({d.replace(hour=h, minute=m)
                     for s in spec
                     if (s["Month"] is None or d.month in s["Month"])
                     and ((d.day in s["Day"] or d.isoweekday() % 7 in s["Weekday"]) if s.get("either") else
                          (s["Day"] is None or d.day in s["Day"]) and (s["Weekday"] is None or d.isoweekday() % 7 in s["Weekday"]))
                     for h in (s["Hour"] or range(24)) for m in (s["Minute"] or range(60))}, reverse=direction < 0)
        yield from (t for t in ts if (t > start if direction > 0 else t <= start))

def nth(gen, n):
    for i, x in enumerate(gen):
        if i == n: return x

# --- what is scheduled on this machine

def launchd_jobs():
    jobs = {}
    if not shutil.which("launchctl") or not C["launch_agents"].is_dir(): return jobs
    for p in sorted(C["launch_agents"].glob("*.plist")):
        try: pl = plistlib.loads(p.read_bytes())
        except Exception: continue
        label = pl.get("Label", p.stem)
        prog = " ".join(pl.get("ProgramArguments") or [pl.get("Program", "")])
        info = subprocess.run(["launchctl", "list", label], capture_output=True, text=True)
        code = re.search(r'"LastExitStatus" = (-?\d+);', info.stdout)
        pid = re.search(r'"PID" = (\d+);', info.stdout)
        cal = pl.get("StartCalendarInterval")
        logs = [Path(pl[k]).expanduser() for k in ("StandardOutPath", "StandardErrorPath") if pl.get(k)]
        stamps = [f.stat().st_mtime for f in logs if f.exists()]
        jobs[label] = {
            "vendor": ".app/Contents/" in prog,
            "loaded": info.returncode == 0,
            "exit": None if pid or not code else int(code.group(1)),  # a running job's last exit is history
            "spec": plist_spec(cal) if cal else None,
            "interval": pl.get("StartInterval"),
            "oneoff": bool(cal) and all("Month" in c and "Day" in c for c in (cal if isinstance(cal, list) else [cal])),
            "daemon": bool(pl.get("KeepAlive") or (pl.get("RunAtLoad") and not cal and not pl.get("StartInterval"))),
            "log_at": dt.datetime.fromtimestamp(max(stamps)).replace(microsecond=0) if stamps else None,
        }
    return jobs

def cron_jobs():
    """Crontab lines as jobs named cron:<script name>; a later line with the same name gets a numeric suffix."""
    jobs = {}
    if not shutil.which("crontab"): return jobs
    tab = subprocess.run(["crontab", "-l"], capture_output=True, text=True).stdout
    for line in tab.splitlines():
        parts = line.split()
        if not parts or line.lstrip().startswith("#") or "=" in parts[0] or len(parts) < 6: continue
        if parts[0].startswith("@"): continue  # @reboot and friends: no calendar to check
        name = "cron:" + Path(parts[5]).name
        while name in jobs: name += "+"
        jobs[name] = {"spec": cron_spec(" ".join(parts[:5])), "loaded": True, "vendor": False, "oneoff": False,
                      "exit": None, "interval": None, "daemon": False, "log_at": None}
    return jobs

# --- the ledger claude-run and ops-check append to

def ledger(now):
    f = C["ledger"]
    runs = []
    for l in f.read_text().splitlines() if f.exists() else []:
        try: r = json.loads(l)
        except ValueError: continue
        if isinstance(r, dict) and r.get("loop") and r.get("date"): runs.append(r)
    if not runs: return {}, None
    by = {}
    for r in runs: by.setdefault(r["loop"], []).append(r)
    since = (now - dt.timedelta(days=WINDOW)).isoformat()
    first = min(r["date"] for r in runs)[:10]
    out = {}
    for loop, rs in by.items():
        checks = [r for r in rs if "check" in r]
        claude = [r for r in rs if "check" not in r]
        win_checks = [r for r in checks if r["date"] >= since]
        win_claude = [r for r in claude if r["date"] >= since]
        if checks:
            last_ok, detail = checks[-1]["check"] == "pass", " ".join((checks[-1].get("detail") or "").split())
            passes, total = sum(r["check"] == "pass" for r in win_checks), len(win_checks)
        else:
            last_ok = not failed(claude[-1])
            detail = f"run ended {claude[-1].get('subtype')} (exit {claude[-1].get('exit')})"
            passes, total = sum(not failed(r) for r in win_claude), len(win_claude)
        last7 = [r["check"] for r in checks[-7:]]
        history = "".join("p" if r["check"] == "pass" else "f" for r in checks[-10:]) if checks else \
                  "".join("f" if failed(r) else "p" for r in claude[-10:])
        out[loop] = {
            "last": max(r["date"] for r in rs), "last_ok": last_ok, "detail": detail[:200],
            "passes": passes, "total": total, "chronic": last7.count("fail") >= 3,
            "fails7": f"{last7.count('fail')} of last {len(last7)}",
            "cost": round(sum(r.get("cost") or 0 for r in win_claude), 2),
            "has_checks": bool(checks), "history": history,
        }
    return out, first

def build():
    now = dt.datetime.now().replace(microsecond=0)
    md = C["registry"].read_text() if C["registry"].exists() else ""
    registry, services = table(md, "Registry"), table(md, "Services")
    jobs = {**launchd_jobs(), **cron_jobs()}
    led, first = ledger(now)
    snap_file = C["out"] / "cloud.json"
    snap = json.loads(snap_file.read_text()) if snap_file.exists() else {"at": None, "routines": [], "tasks": []}
    snap_age_h = (now.astimezone() - dt.datetime.fromisoformat(snap["at"])).total_seconds() / 3600 if snap["at"] else None
    routines = {r["name"]: r for r in snap["routines"]}
    tasks = {t["id"]: t for t in snap["tasks"]}
    window_from = max(first or now.date().isoformat(), (now - dt.timedelta(days=WINDOW)).date().isoformat())
    rows, claimed = [], set()

    def iso(t): return t.isoformat(timespec="minutes") if t else None

    for reg in registry:
        loop, job = reg["Loop"], reg["Job"]
        claimed.add(job)
        kind, _, ref = job.partition(":") if job.startswith(("routine:", "task:")) else ("local", "", job)
        ref = ref or job
        override = re.search(r"`([\d*,\-/ ]+)`", reg.get("Schedule", ""))
        row = {"loop": loop, "project": reg.get("Project", ""), "runtime": reg.get("Runtime", ""), "job": job,
               "schedule": (reg.get("Schedule", "").replace(override.group(0), "") if override else reg.get("Schedule", "")).replace("`", "").strip(" ()"),
               "last_run": None, "result": None, "detail": "", "next_due": None,
               "pass_rate": None, "checks": None, "cost": None, "status": None,
               "checked_by": [c.strip() for c in reg.get("Checked by", "").split(",") if c.strip()]}
        spec, live, j = None, True, None
        if kind == "local":
            j = jobs.get(ref)
            live = bool(j and j["loaded"])
            spec = j and j["spec"]
            if j and j["interval"]: row["next_due"] = f"every {j['interval'] // 60} min"
        else:
            item = (routines if kind == "routine" else tasks).get(ref)
            live = bool(item and item.get("enabled"))
            if item and item.get("cron"): spec = cron_spec(item["cron"])
            if item and item.get("next_run_at"):
                row["next_due"] = iso(dt.datetime.fromisoformat(item["next_run_at"].replace("Z", "+00:00")).astimezone().replace(tzinfo=None))
            if item and item.get("last_finished_at") and loop not in led:
                row["last_run"] = iso(dt.datetime.fromisoformat(item["last_finished_at"].replace("Z", "+00:00")).astimezone().replace(tzinfo=None))
                row["result"] = "pass" if item.get("last_status") == "succeeded" else "fail"
                row["detail"] = f"routine run {item.get('last_status')}"
        if override: spec = cron_spec(override.group(1), both=True)
        if spec and not (row["next_due"] and kind != "local"):
            row["next_due"] = iso(nth(fires(spec, now, 1), 0))
        if not spec and not row["next_due"]:
            row["next_due"] = "on event"
        check = C["checks"] / f"{loop}.py"
        if loop in led:
            l = led[loop]
            row.update(last_run=l["last"][:16], result="pass" if l["last_ok"] else "fail", detail=l["detail"],
                       pass_rate=round(l["passes"] / l["total"], 3) if l["total"] else None,
                       checks=f"{l['passes']} of {l['total']}", cost=l["cost"], history=l["history"])
            if l["chronic"]: row["detail"] = f"{l['fails7']} checks failed. " + row["detail"]
        elif check.exists():  # loops that don't log (cloud routines): the builder runs their plain check
            c = subprocess.run([sys.executable, str(check)], capture_output=True, text=True)
            row["result"] = "pass" if c.returncode == 0 else "fail"
            row["detail"] = (c.stdout or c.stderr).strip()
        elif j and j.get("exit") is not None:  # nothing logged: launchd's last exit and its log file's time
            row.update(result="pass" if j["exit"] == 0 else "fail", last_run=iso(j["log_at"]),
                       detail="" if j["exit"] == 0 else f"last run exited {j['exit']}")
        checked = (loop in led and led[loop]["has_checks"]) or check.exists()
        late = False
        if spec and row["last_run"]:
            prev1, prev2 = nth(fires(spec, now, -1), 0), nth(fires(spec, now, -1), 1)
            late = bool(prev1 and prev2) and now - dt.datetime.fromisoformat(row["last_run"]) > (prev1 - prev2) + dt.timedelta(hours=12)
        row["status"] = ("stale" if kind != "local" and (snap_age_h is None or snap_age_h > STALE_SNAPSHOT_H)
                         else "paused" if not live
                         else "failing" if row["result"] == "fail"
                         else "silent" if late
                         else "no runs yet" if not row["last_run"] and not row["result"]
                         else "chronic" if loop in led and led[loop]["chronic"]
                         else "healthy" if checked
                         else "no check")
        rows.append(row)

    for svc in services:
        claimed.add(svc["Job"])
        j = jobs.get(svc["Job"], {})
        rows.append({"loop": svc["Service"], "project": "Service", "runtime": "mac", "job": svc["Job"],
                     "schedule": svc.get("What it is", ""),
                     "status": "paused" if not j.get("loaded") else "service" if j.get("exit") in (0, None) else "failing",
                     "detail": f"last run exited {j['exit']}" if j.get("exit") not in (0, None) else ""})

    for label, j in jobs.items():
        if label in claimed or j["vendor"] or not j["loaded"]: continue
        runtime = "cron" if label.startswith("cron:") else "mac"
        if j["oneoff"]:
            rows.append({"loop": label, "project": "One-off", "runtime": runtime, "job": label, "status": "one-off",
                         "next_due": iso(nth(fires(j["spec"], now, 1, days=400), 0)), "schedule": "runs once, then removes itself"})
            continue
        rows.append({"loop": label, "project": "Unregistered", "runtime": runtime, "job": label, "status": "unregistered",
                     "next_due": iso(nth(fires(j["spec"], now, 1), 0)) if j["spec"] else None,
                     "schedule": ("crontab line" if runtime == "cron" else "launchd job") + " in no registry or services row"})
    for name, r in routines.items():
        if f"routine:{name}" not in claimed and r.get("enabled") and (r.get("cron") or r.get("last_finished_at")):
            rows.append({"loop": name, "project": "Unregistered", "runtime": "cloud", "job": f"routine:{name}",
                         "status": "unregistered", "schedule": r.get("cron") or "on event"})
    for tid, t in tasks.items():
        if f"task:{tid}" not in claimed and t.get("enabled"):
            rows.append({"loop": tid, "project": "Unregistered", "runtime": "app", "job": f"task:{tid}",
                         "status": "unregistered", "schedule": t.get("cron") or ""})
    names = {r["loop"] for r in rows}
    week = (now - dt.timedelta(days=7)).isoformat()
    for loop, l in led.items():
        if loop not in names and l["last"] >= week:
            rows.append({"loop": loop, "project": "Unregistered", "runtime": "?", "job": "", "status": "unregistered",
                         "last_run": l["last"][:16], "schedule": "logs to the ledger with no registry row"})
    of = scoping(registry)
    for r in rows: r["scope"] = of(r["project"])[1]
    keys = ["loop", "project", "scope", "runtime", "job", "schedule", "status", "last_run", "result", "detail",
            "next_due", "pass_rate", "checks", "cost", "history", "checked_by"]
    rows = [{k: r.get(k) for k in keys} for r in rows]

    meta = [{"label": "Built", "value": now.isoformat(timespec="minutes")},
            {"label": "Pass rate and cost window", "value": f"{window_from} to {now.date()}" + (f" (the ledger starts {first})" if first else " (no ledger yet)")},
            {"label": "Routine snapshot", "value": snap["at"] or "none"},
            {"label": "Cost", "value": "Claude API-equivalent estimate from the ledger; loops that don't run through claude-run aren't metered"},
            {"label": "Refresh", "value": C["refresh"]},
            {"label": "Registry", "value": str(C["registry"]).replace(str(Path.home()), "~")},
            {"label": "Builder", "value": str(Path(__file__).resolve()).replace(str(Path.home()), "~")},
            {"label": "uid", "value": str(os.getuid())}]
    items = waiting(now, of)
    write("loops", rows, meta)
    write("waiting", items, meta[:1])
    html(rows, items, meta)
    return rows

# --- what waits on you

def short(text, cap=72):
    """A scannable title: parentheticals and trailing dates out, cut at the first clause break, then at a word."""
    t = re.sub(r"\s*\([^)]*\)", "", text).strip()
    t = re.sub(r"\s*By \d{4}-\d{2}-\d{2}\.?$", "", t)
    t = re.split(r"; | — |\. (?=[A-Z])|(?<=\?) ", t)[0].rstrip(".")
    head = t.split(": ", 1)[0]
    t = head if len(head) >= 15 and head != t else t
    return t if len(t) <= cap else t[:cap].rsplit(" ", 1)[0] + "…"

def checkouts(owner, roots):
    seen = {}
    for root in (Path(r).expanduser() for r in roots):
        for g in root.glob("**/.git"):
            if "node_modules" in g.parts or len(g.relative_to(root).parts) > 5: continue
            url = subprocess.run(["git", "-C", str(g.parent), "remote", "get-url", "origin"], capture_output=True, text=True).stdout.strip()
            m = re.search(rf"github\.com[:/]{re.escape(owner)}/([^/.]+)", url)
            if m: seen.setdefault(m.group(1), g.parent)
    return seen

def memo_items(owner, repo, path, cfg):
    """Open decisions in a checkout's docs/ on its default branch: bullets under a `decisions` heading (closed once
    every `**Decision:**` line is filled), and table rows whose last cell is the `awaiting` status."""
    heading, awaiting = cfg.get("decisions", "Founder decisions"), cfg.get("awaiting", "Awaiting founder")
    subprocess.run(["git", "-C", str(path), "fetch", "-q", "origin"], capture_output=True)
    ref = subprocess.run(["git", "-C", str(path), "rev-parse", "--abbrev-ref", "origin/HEAD"], capture_output=True, text=True).stdout.strip() or "origin/main"
    hits = subprocess.run(["git", "-C", str(path), "grep", "-l", "-i", "-e", heading, "-e", awaiting, ref, "--", "docs"],
                          capture_output=True, text=True).stdout.split()
    items = []
    for hit in hits:
        file = hit.split(":", 1)[1]
        text = re.sub(r"^```.*?^```", "", subprocess.run(["git", "-C", str(path), "show", hit], capture_output=True, text=True).stdout,
                      flags=re.M | re.S)  # templates in fenced blocks aren't open decisions
        link = f"https://github.com/{owner}/{repo}/blob/{ref.split('/', 1)[1]}/{file}"
        src = {"kind": "Memo decision", "tag": "Decision", "source": f"{repo} · {Path(file).stem}", "where": f"{repo}/{file}", "link": link, "repo": repo}
        sec = re.search(rf"^#+ {re.escape(heading)}\s*\n(.*?)(?=^#|\Z)", text, re.M | re.S | re.I)
        decisions = re.findall(r"\*\*Decision:\*\*\s*(.*)", text)
        answered = decisions and all(d.strip() and d.strip() != "approve / reject / defer" for d in decisions)
        for line in (sec.group(1).splitlines() if sec and not answered else []):
            if line.lstrip().startswith(("- ", "* ")):
                item = line.lstrip()[2:].strip()
                due = re.search(r"\bBy (\d{4}-\d{2}-\d{2})", item)
                items.append({**src, "item": item, "due": due.group(1) if due else None})
        rows = [l.strip("| ").split("|")[0].strip().replace("`", "") for l in text.splitlines()
                if l.startswith("|") and re.search(rf"\|\s*{re.escape(awaiting)}\s*\|?\s*$", l, re.I)]
        if rows:
            items.append({**src, "title": f"{len(rows)} items in {Path(file).stem} await your call",
                          "item": f"{len(rows)} rows awaiting your call: " + "; ".join(rows),
                          "action": "mark each row's decision", "due": None})
    return items

def waiting(now, of):
    cfg, items = C["waiting"], []
    q = cfg.get("queue")
    if q and Path(q["path"]).expanduser().exists():
        for line in Path(q["path"]).expanduser().read_text().splitlines()[2:]:
            f = [x.strip() for x in line.split("|")]
            if len(f) == 7 and f[3] == q["owner"]:
                items.append({"kind": "Queue", "source": "Queue", "item": f[2], "action": f[4], "where": f"queue ({f[1]})",
                              "tag": "Decision" if f[1] == "decision" or f[4].lower().startswith(("decide", "pick")) else "To do",
                              "link": q.get("link"), "due": f[0]})
    gh = cfg.get("github")
    if gh and GH:
        res = subprocess.run([GH, "search", "prs", "--owner", gh["owner"], "--label", gh.get("label", "founder"), "--state", "open",
                              "--json", "repository,number,title,createdAt,url", "--limit", "100"], capture_output=True, text=True)
        for p in json.loads(res.stdout) if res.returncode == 0 else []:
            items.append({"kind": "PR", "tag": "PR review", "source": f"{p['repository']['name']}#{p['number']}",
                          "item": p["title"], "action": "review: merge or close",
                          "where": f"{p['repository']['nameWithOwner']}#{p['number']}", "link": p["url"], "due": None,
                          "repo": p["repository"]["name"],
                          "since": p["createdAt"][:10]})
        if gh.get("memo_roots"):
            for repo, path in sorted(checkouts(gh["owner"], gh["memo_roots"]).items()):
                items += memo_items(gh["owner"], repo, path, gh)
    keys = ["title", "tag", "source", "kind", "item", "action", "where", "link", "due", "since"]
    return sorted(({**{k: i.get(k) for k in keys}, "title": i.get("title") or short(i["item"]),
                    **dict(zip(("project", "scope"), of(i.get("repo"))))} for i in items),
                  key=lambda i: (i["due"] or "9999", i["kind"]))

# --- output

def write(name, rows, meta):
    C["out"].mkdir(parents=True, exist_ok=True)
    (C["out"] / f"{name}.json").write_text(json.dumps({"rows": rows, "meta": meta}, indent=1, ensure_ascii=False) + "\n")

def html(rows, items, meta):
    """The same page the claude.ai dashboard runs, with a local stand-in for its runtime and the data inlined."""
    data = json.dumps({"loops": {"rows": rows, "meta": meta}, "waiting": {"rows": items, "meta": meta[:1]},
                       "look": json.loads((ROOT / "dashboard/look.json").read_text()),
                       "params": json.loads((ROOT / "dashboard/params.json").read_text())}, ensure_ascii=False).replace("</", "<\\/")
    page = (ROOT / "dashboard/index.html").read_text()
    shim = (ROOT / "dashboard/local.js").read_text()
    (C["out"] / "dashboard.html").write_text(
        '<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
        f'<title>Loop fleet</title></head><body>\n<script>window.FLEET = {data};</script>\n<script>{shim}</script>\n'
        f'<div id="dash-root">\n{page}\n</div>\n</body></html>\n')

if __name__ == "__main__":
    rows = build()
    counts = {}
    for r in rows: counts[r["status"]] = counts.get(r["status"], 0) + 1
    print(json.dumps(counts), "->", C["out"] / "dashboard.html")
