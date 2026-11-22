---
name: plan-loops
description: Read a project and propose the scheduled agent loops it needs, then build the ones the user approves (charter, outcome check, schedule, registry row). Use when the user starts a new project, asks what loops or automation a product needs, wants to "put a project on autopilot", or asks which of their projects lacks a loop it should have. Not for checking loops already running (that's fleet).
---

# Plan loops

KIT is the agent-ops-kit folder: two levels up from this skill's base directory. The menu is `KIT/docs/LOOP_CATALOG.md`; the charter template is `KIT/docs/AGENT_LOOP.md`. Read both first.

The aim is the fewest loops that cover the product's real risks, each one checked by something that doesn't trust the agent. More loops mean more to watch: a project starts with one to three.

## 1. Read the project

Look before you ask. From the repo and what it connects to, find:
- **Users and money:** is it live, does anyone pay, how (Stripe, app stores, ads)? Analytics in use?
- **What can break:** deploys and how (Vercel, a VPS, an app store), tests and e2e journeys, an uptime probe, crons it already runs.
- **Who talks to it:** a support inbox or widget, reviews, a community, social accounts.
- **Growth:** SEO pages, content, ads, a launch coming.
- **Loops it already has:** the user's registry (`$AGENT_OPS_DIR/REGISTRY.md`, default `~/.agent-ops`), the repo's own `docs/*LOOP*.md`, crontabs and workflows.

Then ask only what the repo can't tell you, and at most three questions: how much of their attention this project gets, what would hurt most if it broke unnoticed, and what they'd spend a month on it.

## 2. Propose

For each loop from the catalog whose "needs it when" holds, say in one line why this project needs it, then give its trigger and cadence, runtime (cloud for anything a customer waits on), outcome check (what it reads that the run didn't write), **checked by**, and a cost range. Order by what hurts most if it's missing. Also name the catalog loops you're leaving out and why, and any loop the project already has that the catalog says it doesn't need.

Stop and wait for the user to pick.

## 3. Build each approved loop

One at a time, and run each by hand before scheduling it:
1. **Charter** in the project's `docs/`, from `KIT/docs/AGENT_LOOP.md`, every placeholder filled from what you read. Its merge policy names this project's X surfaces.
2. **Outcome check:** a script with no model in it that exits 0 only when the run did its job, reading at least one fact the run didn't write (the PR exists, the post reads back, the report has every section). Save it as `$AGENT_OPS_DIR/checks/<loop>.py` when nothing else runs it.
3. **Runner:** calls `KIT/bin/claude-run` with the charter, exports `OPS_LOOP=<loop>`, and ends with `KIT/bin/ops-check -- <check>`. `KIT/scripts/run.sh` is a starting point.
4. **Hand run.** Run it once and read the output and the check's line in the ledger. Fix the loop or the check until a good run passes and a broken one fails.
5. **Schedule** it on the user's yes: launchd or cron for local loops, a Claude Code routine for cloud ones.
6. **Register** it in the same change: a row in the registry, with its Checked by. Rebuild the fleet (`python3 KIT/fleet/fleet.py`) and confirm it shows as healthy or not run yet, not Unregistered.

Report what you built, what each loop costs per run from its hand run, and the first date its check will run on its own.
