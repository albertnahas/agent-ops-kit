---
name: loop-health
description: Scan this machine's scheduled agent loops (launchd jobs, crontab lines, and Claude Code cloud routines and desktop tasks once synced) and show whether each one is healthy on a local dashboard. No registry, ledger or config needed. Use when the user asks whether their loops, cron jobs or scheduled agents are running, what failed or went quiet, or to see them all on one page.
---

# Loop health

KIT is two levels up from this skill's base directory; it holds `fleet/fleet.py`, a builder with no model in it. OPS is `$AGENT_OPS_DIR`, default `~/.agent-ops`. `KIT/fleet/README.md` says what the builder reads and how each status is decided.

Observe, don't change. Never edit, reload, unload or run a job unless the user asked for that job by name. Scheduling anything needs their yes first.

1. **Scan.** `python3 KIT/fleet/fleet.py`. With no registry at `OPS/REGISTRY.md` it lists every loaded job it finds, skipping the vendors' own (programs inside `.app` bundles). It prints the count per status and the page's path.
2. **Open.** `open OPS/fleet/dashboard.html` (`xdg-open` on Linux).
3. **Tell them what's wrong.** Read `OPS/fleet/loops.json`. Lead with Failing, then Silent, each with its detail line. Before you explain a failure, read the end of that job's log: the plist's `StandardErrorPath` or `StandardOutPath`, or the file the crontab line sends its output to. Then one line on the rest.
4. **Say what it can't see.** Without a run ledger, last run and exit come from launchd and from the time a job's log last changed. Cron keeps no exit codes, and a crontab line with no output file has no record of its runs at all. Nothing here says whether a run did its job, only whether it ran and how it exited.
5. **Offer cloud routines, once.** Claude Code cloud routines and desktop-app tasks aren't on the machine. On their yes, follow step 1 of `KIT/fleet/SYNC.md` (the snapshot, read-only) and rebuild. Skip the rest of that file: it needs a claude.ai dashboard the full kit's `fleet` skill sets up.
6. **Offer to keep it fresh, once.** A launchd job (macOS) or crontab line running `python3 KIT/fleet/fleet.py` every 30 minutes. Add it only on their yes.

If `OPS/REGISTRY.md` exists, the page is the full fleet view instead. That's the `fleet` skill's territory; point them there.
