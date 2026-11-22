---
name: fleet
description: See and manage every scheduled agent loop you run, across all projects, on one dashboard. Use when the user wants to set up the fleet dashboard, open it, find out which loops are failing or silent, register a running job, retire a loop, or get the dashboard on claude.ai. Not for designing new loops for a project (that's plan-loops).
---

# Fleet

KIT is the agent-ops-kit folder: two levels up from this skill's base directory. OPS is `$AGENT_OPS_DIR`, default `~/.agent-ops`. Everything the dashboard shows comes from `KIT/fleet/fleet.py`; `KIT/fleet/README.md` says what it reads and how each status is decided. Read that README before you start.

Observe, don't change: never edit, reload or unload a job the user already runs unless they asked for that job by name. Scheduling something new, writing to their crontab and creating a scheduled task each need their yes first.

## Set up

1. Make OPS. Write `OPS/fleet.json` from `KIT/fleet/fleet.example.json`: their GitHub login (`gh api user -q .login`) if `gh` is signed in, where their repos live for `memo_roots`, and drop the `queue` block unless they keep a queue file. Ask only what you can't find.
2. Inventory. Run `python3 KIT/fleet/fleet.py` once with no registry. Every scheduled job shows as Unregistered in `OPS/fleet/loops.json`. Leave out the vendors' own jobs (the builder already hides programs inside `.app` bundles).
3. Draft `OPS/REGISTRY.md` from `KIT/fleet/REGISTRY.example.md`: one row per loop, from each job's plist or crontab line, its log files and the script it runs. A job with no model in it that runs all the time or only watches goes under Services. Fill **Checked by** from `KIT/docs/LOOP_CATALOG.md` and what the job's script reads. Leave a cell empty rather than guess, and say which ones you couldn't fill.
4. Show the user the table and get their yes before you write it.
5. Keep it fresh: offer a launchd job (macOS) or crontab line running `python3 KIT/fleet/fleet.py` every 30 minutes, and on their yes add it and its Services row.
6. Build and open: `python3 KIT/fleet/fleet.py && open OPS/fleet/dashboard.html` (`xdg-open` on Linux).

To give loops a ledger, their runners call `KIT/bin/claude-run` instead of `claude -p`, end with `KIT/bin/ops-check -- <check>`, and export `OPS_LOOP=<registry name>`. Offer this per loop; don't rewrite runners on your own.

## Day to day

- **What's wrong?** Build, then read `OPS/fleet/loops.json`: failing, silent, flaky and unregistered first, each with its detail line. Read the ledger lines behind a failure before you explain it.
- **Register a job:** add its row, rebuild, and confirm it no longer shows as Unregistered.
- **Retire a loop:** ask the reason, show exactly what you'll remove, wait for yes. Then stop and remove its schedule (`launchctl bootout gui/$(id -u)/<label>` and move its plist out of LaunchAgents; delete the crontab line; disable the routine or task), delete its registry row, follow any retirement rules the registry file names, rebuild and confirm it's gone. Keep its charter.

## On claude.ai (optional)

A private claude.ai dashboard adds Claude Code cloud routines and desktop-app tasks, and opens on any device. It needs the claude.ai Data dashboard type and a desktop app with scheduled tasks; if either isn't there, say so and stop.

1. Create a dashboard from the Data type, titled "Loop fleet". Upload `OPS/fleet/loops.json` and `waiting.json` as assets. In one batch write `dash/meta` (`{"title": "Loop fleet"}`), `dash/look` (`KIT/fleet/dashboard/look.json`), `datasets/loops` and `datasets/waiting` (file sources pointing at the uploads, format json, with `updated`), and `files/index.html` (`{"text": <KIT/fleet/dashboard/index.html>}`). Read `check` in `data/users/me` until it passes.
2. Add `"artifact": "<its url>"` to `OPS/fleet.json`.
3. On the user's yes, create a desktop scheduled task `fleet-sync` (for example `45 9,21 * * *`) whose prompt says to follow `KIT/fleet/SYNC.md` exactly, and give it a registry row checked by `you`.
