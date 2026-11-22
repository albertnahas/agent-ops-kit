# Fleet dashboard

One page for every scheduled loop you run, across all your projects: whether each one is healthy, when it runs next, what it cost, who checks its output, and everything waiting on you. `fleet.py` builds it with no model, so it's free to rebuild as often as you like.

```bash
python3 fleet/fleet.py && open ~/.agent-ops/fleet/dashboard.html
```

It works with nothing set up: an empty fleet shows as such. It gets useful once your loops have a registry (`REGISTRY.example.md`) and log through `bin/claude-run` and `bin/ops-check`. The `fleet` skill sets all of this up for you and never changes a job you already run.

## What it reads

| Source | Gives | Needed |
|---|---|---|
| `REGISTRY.md` | the loops, their project, schedule, charter, check and who checks their output; the services | yes, or every job shows as Unregistered |
| launchd (`~/Library/LaunchAgents`) and your crontab | what is actually scheduled, last exit, next run | found on its own |
| `runs.jsonl` | last run, pass rate, cost, the last 10 outcomes | once loops run through `claude-run` and `ops-check` |
| `checks/<loop>.py` | an outcome for loops that write no ledger line, like cloud routines | per loop |
| `fleet/cloud.json` | Claude Code cloud routines and desktop-app tasks: schedule, next and last run | only with the claude.ai sync (`SYNC.md`) |
| GitHub, a queue file, decision memos | what waits on you: PRs with your label, owner-you queue lines, open decisions in your repos' `docs/` | optional, `waiting` in `fleet.json` |

Without a ledger, a launchd loop's last exit and the time its log file last changed stand in for its last run, so a fleet you haven't instrumented still shows what failed.

## Statuses

- **Failing:** the last outcome check failed (or, with no check, the last run exited non-zero).
- **Silent:** no run for one scheduled period plus 12 hours.
- **Flaky:** the last check passed but 3 of the last 7 failed.
- **Unregistered:** running, with no registry row.
- **Stale data:** the cloud snapshot is over 36 hours old.
- **Unchecked:** runs, with nothing the builder can read that proves the outcome.
- **Not run yet**, **Paused** (registered, not loaded or enabled), **Healthy**.

## Factory

The Factory tab draws who checks what: every loop on the left, the loops and scripts that read other loops' output in the middle, and you on the right. A loop's **Checked by** cell draws its lines. A name there is a loop's or service's name or its job (with or without `routine:` or `task:`), or `you`; any other name shows as a checker that isn't in the registry. Loops with no checker run into **Nobody**, the gap to close. Tap or point at a loop to trace its chain both ways. With a project picked at the top, it draws that project's loops and every loop their output reaches, so each chain stays whole.

## Config

`$AGENT_OPS_DIR/fleet.json` (default `~/.agent-ops/fleet.json`; `FLEET_CONFIG` overrides the path). Every key is optional; `fleet.example.json` shows them all. Paths default to the same folder: `REGISTRY.md`, `runs.jsonl`, `checks/`, and `fleet/` for the output.

## Projects and General

The picker at the top of the page narrows every tab to one project: the overview's status line, numbers and lists, the loops and what waits on you. General holds what belongs to no one product: loops with no project, the projects you list under `general` in `fleet.json` (say your ops and personal loops), services, one-off and unregistered jobs, and queue lines. A PR or an open decision belongs to the registry project its repo is named after, ignoring case and punctuation (`social-algorithms` is Social algorithms), and to General otherwise. Each row carries the result as `scope`, so the page never repeats the rule; within General, the Loops tab still shows each project's own card.

## Keeping it fresh

The build is a service, not a loop: schedule `python3 fleet/fleet.py` every 30 minutes with launchd or cron, and list it under Services in your registry. The claude.ai dashboard (`SYNC.md`) is an optional second view: it adds your cloud routines and desktop tasks, and opens on any device you're signed in on.

## Actions

The page can't change your machine, so each action copies something for you to run: launchd's run-now and stop commands, and a retire prompt you paste into Claude Code. The prompt asks for your reason, shows what it will remove and waits for your yes before it unloads the job and deletes its registry row.
