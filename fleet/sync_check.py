#!/usr/bin/env python3
"""Outcome check for SYNC.md: the receipt names two uploads, is no older than the data files fleet.py wrote (so the
dashboard shows what the builder holds), carries the page it published, and the cloud snapshot was taken in the same run."""
import datetime as dt, hashlib, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fleet import C

D = C["out"]
rec = json.loads((D / "receipt.json").read_text()) if (D / "receipt.json").exists() else {}
snap = json.loads((D / "cloud.json").read_text()) if (D / "cloud.json").exists() else {}
at = dt.datetime.fromisoformat(rec["at"]).timestamp() if rec.get("at") else 0
page = hashlib.sha256((Path(__file__).resolve().parent / "dashboard/index.html").read_bytes()).hexdigest()
bad = []
if set(rec.get("blobs", {})) != {"loops", "waiting"}: bad.append("receipt lacks the two uploads")
if at < max((D / f).stat().st_mtime for f in ("loops.json", "waiting.json")): bad.append("data files changed after the last upload")
if rec.get("page") != page: bad.append("the dashboard runs an older page than the kit's")
if not snap.get("at") or abs(at - dt.datetime.fromisoformat(snap["at"]).timestamp()) > 3600:
    bad.append(f"cloud snapshot from {(snap.get('at') or 'never')[:16]}, not this run")
if any(set(r) != {"name", "enabled", "cron", "next_run_at", "last_status", "last_finished_at"} for r in snap.get("routines", [])):
    bad.append("cloud snapshot not in the fleet.py shape")
print("; ".join(bad) or f"dashboard synced at {rec['at'][:16]}, {len(snap.get('routines', []))} routines")
sys.exit(1 if bad else 0)
