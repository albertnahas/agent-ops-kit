# agent-ops-kit

The setup I use to run a live product on a night shift of Claude Code agents while I work my day job. They answer support tickets, fix the bugs behind them, open PRs, grade them and merge them. I see only what a revert can't undo.

On [OpenWhen](https://www.openwhen.cards), a product I built and run alone, 286 PRs have merged since July 2026 (as of 22 Nov). The loops opened 172 of them, 78 of which are daily reports. The rest came from Claude Code sessions I directed and a few dependency bots. No loop PR has been reverted. The one revert on main since July undid a pricing change I pushed myself.

Running more than one loop? [agent-ops-factory](https://github.com/albertnahas/agent-ops-factory) builds on this kit with a playbook, a loop planner and one dashboard for every loop.

## Your first loop in 15 minutes

One real loop, start to finish, on a Mac. The example is `readme-links`: each morning it checks the links in your repo's README and writes a report. It needs no API key or service beyond the Claude Code and `gh` logins you already have. On Linux, pass `--runtime cron`, then use the schedule command new-loop prints and the hard stop in the charter's Kill switch instead of the launchd ones. The paths below assume `AGENT_OPS_DIR` is unset, so it's `~/.agent-ops`.

1. **Prerequisites.** The tools listed under [Start a loop](#start-a-loop), plus `git` and a repo of yours with a README and an `origin` you can push to.
2. **Clone the kit**, then run its tests as in [By hand](#by-hand):

   ```bash
   git clone https://github.com/albertnahas/agent-ops-kit && cd agent-ops-kit && KIT=$PWD
   ```

3. **Scaffold the loop** from your repo. Budget and turns default to $5 and 60 a run, and the hard limits to the default in `skills/new-loop/questions.json`:

   ```bash
   cd /path/to/your-repo
   "$KIT/bin/new-loop" --name readme-links --runtime launchd --schedule '0 9 * * *' \
     --mission 'Keep every link in README.md working. Never change anything but README.md.' \
     --source 'the links in README.md on the default branch' \
     --floor 'unmeasured: no broken-link count yet'
   ```

4. **What it wrote.** It won't overwrite any of these, and it prints its next steps:
   - `docs/loops/readme-links.md`: the charter, the agent's only instructions, with your words in its mission blocks.
   - `docs/orders/readme-links.md`: its Orders, empty for now, which change only by an Orders PR.
   - `~/.agent-ops/checks/readme-links.py`: the outcome check, plain Python with no model.
   - `~/.agent-ops/runners/readme-links.sh`: the runner. It checks the charter's `status:` line, runs Claude with the caps, then the check.
   - `~/.agent-ops/schedules/com.agent-ops.readme-links.plist`: the launchd schedule. It isn't installed yet.
   - A row in `~/.agent-ops/REGISTRY.md`, and copies of the grader, hooks, `bin/claude-run`, `bin/ops-check`, `scripts/mission-guard` and `docs/DECISIONS.md` if your repo lacks them.
5. **The outcome check.** new-loop fills it from your Floor. With an unmeasured Floor it checks one thing: `docs/ops-reports/readme-links/<today>.md` is on a branch of origin with every report section. A measured Floor also takes `--measure` (see [the skill's step 2](skills/new-loop/SKILL.md#2-write-the-check-before-anything-else)). Dry run it:

   ```bash
   python3 ~/.agent-ops/checks/readme-links.py
   ```

   Before the first run it should fail with `no docs/ops-reports/readme-links/<today>.md on any branch of origin`. Anything else, like `can't fetch origin`, gets fixed now.
6. **Land and bless.** Merge the repo files it listed through a PR. If the repo has no grade labels yet, create them as in [By hand](#by-hand). Then `git pull` and run the `scripts/mission-guard bless ...` line it printed, yourself.
7. **Run it once by hand**, which runs Claude through `bin/claude-run` and the check through `bin/ops-check`:

   ```bash
   ~/.agent-ops/runners/readme-links.sh
   cat ~/.agent-ops/logs/readme-links.log
   tail -2 ~/.agent-ops/runs.jsonl
   ```

   The first ledger line is the run, with its `exit`, `turns` and `cost`. The second is the ops-check line, `{"loop":"readme-links","date":"...","check":"pass","detail":"..."}`. That `check` is the verdict, not Claude's exit code. On a `fail`, `detail` says why.
8. **The heartbeat.** Run `"$KIT/bin/heartbeat.py"`. It reads the ledger and alerts on a failed check, a silent loop or a run over 3x its usual cost. With `AGENT_OPS_NOTIFY` unset it prints the alerts. Schedule it every morning with the heartbeat line in [examples/crontab](examples/crontab).
9. **Install the schedule** with the command new-loop printed. With the default paths it's:

   ```bash
   cp ~/.agent-ops/schedules/com.agent-ops.readme-links.plist ~/Library/LaunchAgents/ && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agent-ops.readme-links.plist
   ```

10. **Stop it.** To pause, set `status: paused` on the charter's status line and push to main, as its Kill switch says. The runner reads that line in your checkout before Claude starts. To stop it for good, run the hard stop from the charter's Kill switch:

    ```bash
    launchctl bootout gui/$(id -u)/com.agent-ops.readme-links; rm ~/Library/LaunchAgents/com.agent-ops.readme-links.plist
    ```

Then read every report and grade for the first week, as [Start a loop](#start-a-loop) says.

## What's inside

**The night shift**

- **Front desk:** a support agent answers each ticket within minutes through one API that checks every reply on the server, or escalates it to you with a decision you make in one tap. `examples/support-agent/`
- **Mechanic:** "Fix it now" on an escalation wakes a fix agent. It opens a PR, and the person hears back only once the fix is live. `examples/support-agent/SUPPORT_FIX.md`
- **Inspector:** a fresh-context grader grades every PR A, B, C or X. It never saw the author's reasoning, only the merge policy, the PR body and the diff. `.claude/agents/pr-grader.md`
- **Watchman:** every run is logged with its cost and judged by a free outcome check, not by Claude's exit code. A heartbeat alerts you on a failed, silent or costly loop, and a second watchman in the cloud alerts you if the heartbeat stops. `bin/`, `checks/`

**The rules they work by** (`docs/AGENT_LOOP.md`)

- **Blast radius:** A merges itself, B gets fixed then merged, C gets closed, X waits for you. X means a revert won't fully undo it: money, data-destroying migrations, auth, secrets, new dependencies, paid API spend, deleting user data, the policy itself. The charter also lists what isn't X. Without that list a careful grader escalates everything and the real escalations drown.
- **Proof videos:** every PR a user would see ships a phone-width Playwright video of the journey. Tests pass while artwork is hidden. A video doesn't.

## Start a loop

You need Claude Code v2.1.295 or later, `gh`, `jq` and `python3`. Install the plugin:

```
/plugin install agent-ops-kit --marketplace albertnahas/agent-ops-kit
```

Then, in the repo you want a loop on, run `/agent-ops-kit:new-loop`, or just ask Claude Code for a new loop. It asks what the loop should achieve, how you'll know it worked, the least it may deliver and where that number lives, when and where it runs, and which project it's for. Everything else starts from a default it tells you once, and you can change any of it in the charter later. [docs/RUNTIMES.md](docs/RUNTIMES.md) settles where: a cloud routine, launchd, cron or a desktop app task. Then `bin/new-loop` writes the loop the same way every time:

- the charter in `docs/loops/<name>.md`, with your words in its Mission (and the Floor and Source inside it), hard limits and kill switch, and its Orders in `docs/orders/<name>.md`;
- the outcome check in `$AGENT_OPS_DIR/checks/<name>.py`, written before the loop's first prompt: today's report landed, and the number in your Floor holds;
- a runner that exports `OPS_LOOP` with a budget and turn cap, and a schedule file it doesn't install;
- a row in `$AGENT_OPS_DIR/REGISTRY.md`, or wherever `AGENT_OPS_REGISTRY` points;
- whatever the charter relies on that the repo lacks: the grader, the hooks, `claude-run`, `ops-check` and `scripts/mission-guard`.

To change a loop later, run `/agent-ops-kit:new-loop edit <loop>`. Each change goes the way it should: an Orders PR, a founder PR for anything in a mission block, the status line for a pause, `new-loop --reschedule` for a move, or retirement.

The skill dry runs the check, then leaves three steps to you: merge the PR, bless the charter at your own terminal, and say yes to the schedule. Watch the first week. Read every report and every grade before you trust it.

Protect main if your plan allows it. The guard hook is a speed bump. Branch protection is the wall.

### By hand

The same thing without the plugin:

```bash
git clone https://github.com/albertnahas/agent-ops-kit && cd agent-ops-kit
```

```bash
tests/hooks.test.sh && tests/ops.test.sh && tests/new-loop.test.sh
```

Every line should say `ok`, or `skip` for the factory check when you don't have the factory. Then run `bin/new-loop --help` and follow what it prints, or copy the pieces yourself:

```bash
cp -R .claude bin checks docs scripts tests /path/to/your-repo/
```

```bash
cd /path/to/your-repo && for l in founder grade:A grade:B grade:C grade:X; do gh label create "$l"; done; gh repo edit --delete-branch-on-merge
```

1. Fill in every `<placeholder>` in `docs/AGENT_LOOP.md` and add your own X surfaces.
2. Run one loop by hand with `scripts/run.sh`, then `bin/heartbeat.py`. Read `logs/agent.log` and `~/.agent-ops/COSTS.md`.
3. Schedule both (`examples/crontab`), or make the loop a cloud scheduled task with `examples/cloud-task-prompt.md`. Add the cloud watcher from `examples/heartbeat-watch-prompt.md`.

The plugin's scripts are on your path, but the charter, the grader, the hooks and the checks belong in your repo. The grader stays a copy rather than a plugin agent because its Bash limit is a frontmatter hook, and Claude Code ignores frontmatter hooks on agents loaded from a plugin.

The support agent comes later. It needs a product with a ticket table and a deploy you trust.

## Files

| File | What it does |
|---|---|
| `docs/AGENT_LOOP.md` | The charter: mission, kill switch, data sources, KPIs, the graded merge policy, what each run does and the report format. The agent's only instruction set. |
| `.claude/agents/pr-grader.md` | The grader. A frontmatter hook limits its Bash to `gh pr view` and `gh pr diff`. |
| `.claude/hooks/guard-bash.sh` | Blocks force pushes and pushes to main, so the agent works through PRs. |
| `.claude/settings.json` | Wires the guard with `onFailure: block`, so a broken hook stops the call instead of letting it through. Adds deny rules. |
| `skills/new-loop/`, `bin/new-loop` | The `/new-loop` skill and the script it calls. `questions.json` holds the questions, which the skill, the script's flags and the fleet dashboard's form all read. The script fills the charter from `docs/AGENT_LOOP.md` and the check, runner and registry from `templates/new-loop/`, and exits if the charter template gains a placeholder it can't fill. |
| `docs/RUNTIMES.md` | Where a loop runs (cloud, Mac, app task or a plain script), what each runtime costs, and the rule that every one leaves a ledger line. |
| `scripts/run.sh` | Runs one loop with turn and budget caps, after checking the charter's pause line, and ends with the outcome check. |
| `bin/claude-run` | Drop-in for `claude -p`. Logs each run's exit, turns and cost to `$AGENT_OPS_DIR/runs.jsonl` (default `~/.agent-ops`). |
| `bin/ops-check` | Runs an outcome check and logs pass or fail to the same ledger, with the loop's North Star the check prints: `good: <value> <higher|lower> [<bar>]` for a level, `good: <total> total [<bar>]` for a running total read as its 7-day gain. |
| `checks/report-landed.sh` | Example check: today's report landed, on main or its PR branch, with every section. Write one per loop; it's the only definition of "done" that doesn't trust the agent. |
| `bin/heartbeat.py` | Alerts through `$AGENT_OPS_NOTIFY` on a failed check, a silent loop, a run over 3x its usual cost or a charter's mission blocks changing, at most every 3 days per alert. Writes `COSTS.md`. Your own checks go in `$AGENT_OPS_DIR/heartbeat.d/` as executables that read the alerts as JSON and print them back, adding, replacing or dropping; the notifier gets the due alerts by key on stdin, so it can route each one. |
| `bin/mission-guard` | Guards the text inside each charter's `mission` markers. `bless` records it from the default branch; `check` (run by the heartbeat) alerts with a diff when it changes; `pr` makes a PR that changes it, the guard, the grader, hooks or CI workflows X; `orders` checks an Orders-only PR. `author <n>` exits 1 unless the PR's author can push to the repo, so the sweep makes a stranger's PR X before anything reads it. Product repos keep a copy at `scripts/mission-guard`, and `examples/mission-guard.yml` runs it as a required check. |
| `scripts/night-summary.sh` | What merged, closed and escalated overnight, plus any reverts. |
| `scripts/loop-stats.sh` | Your track record as JSON: commits and merged PRs per month, reverts, escalations. Publish it. |
| `tests/` | Feeds known commands to both hooks, and fixture ledgers to `ops-check` and the heartbeat. `new-loop.test.sh` scaffolds loops in a sandbox and fails unless they bless, pass their own check and pass the factory's `fleet.py --check`. |
| `examples/` | A crontab, cloud task prompts for the loop and the cloud watcher, a GitHub Actions workflow that grades in CI, one that runs the mission guard as a required check, and the support agent. |

## Limits, honestly

- The grader is the same model as the author. Its only independence is that it never saw the author's context. That's worth a lot, and it isn't a second opinion from a different mind.
- "Verified" for UI means the author rendered the page and attached a screenshot and console output. That evidence still comes from the author, and it's the weakest link.
- This has run on one product with one human. If you run it on a team, I'd like to hear what breaks.

MIT licensed. By [Albert Nahas](https://github.com/albertnahas).
