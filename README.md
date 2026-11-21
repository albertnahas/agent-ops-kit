# agent-ops-kit

The setup I use to run a live product on a night shift of Claude Code agents while I work my day job. They answer support tickets, fix the bugs behind them, open PRs, grade them and merge them. I see only what a revert can't undo.

On [OpenWhen](https://www.openwhen.cards), a product I built and run alone, this setup has merged 157 PRs since July 2026. 114 came from the scheduled loop and the rest from Claude Code sessions I directed. One was reverted.

## What's inside

**The night shift**

- **Front desk:** a support agent answers each ticket within minutes through one API that checks every reply on the server, or escalates it to you with a decision you make in one tap. `examples/support-agent/`
- **Mechanic:** "Fix it now" on an escalation wakes a fix agent. It opens a PR, and the person hears back only once the fix is live. `examples/support-agent/SUPPORT_FIX.md`
- **Inspector:** a fresh-context grader grades every PR A, B, C or X. It never saw the author's reasoning, only the merge policy, the PR body and the diff. `.claude/agents/pr-grader.md`
- **Watchman:** every run is logged with its cost and judged by a free outcome check, not by Claude's exit code. A heartbeat alerts you on a failed, silent or costly loop, and a second watchman in the cloud alerts you if the heartbeat stops. `bin/`, `checks/`

**The rules they work by** (`docs/AGENT_LOOP.md`)

- **Blast radius:** A merges itself, B gets fixed then merged, C gets closed, X waits for you. X means a revert won't fully undo it: money, data-destroying migrations, auth, secrets, new dependencies, paid API spend, deleting user data, the policy itself. The charter also lists what isn't X. Without that list a careful grader escalates everything and the real escalations drown.
- **Proof videos:** every PR a user would see ships a phone-width Playwright video of the journey. Tests pass while artwork is hidden. A video doesn't.

## Try it in 5 minutes

You need Claude Code v2.1.295 or later, `gh`, `jq` and `python3`.

```bash
git clone https://github.com/albertnahas/agent-ops-kit && cd agent-ops-kit
```

```bash
tests/hooks.test.sh && tests/ops.test.sh
```

Every line should say `ok`. Then copy it into your repo:

```bash
cp -R .claude bin checks docs scripts tests /path/to/your-repo/
```

```bash
cd /path/to/your-repo && for l in founder grade:A grade:B grade:C grade:X; do gh label create "$l"; done; gh repo edit --delete-branch-on-merge
```

1. Fill in every `<placeholder>` in `docs/AGENT_LOOP.md` and add your own X surfaces.
2. Run one loop by hand with `scripts/run.sh`, then `bin/heartbeat.py`. Read `logs/agent.log` and `~/.agent-ops/COSTS.md`.
3. Schedule both (`examples/crontab`), or make the loop a cloud scheduled task with `examples/cloud-task-prompt.md`. Add the cloud watcher from `examples/heartbeat-watch-prompt.md`.
4. Protect main if your plan allows it. The guard hook is a speed bump. Branch protection is the wall.
5. Watch the first week. Read every report and every grade before you trust it.

The support agent comes later. It needs a product with a ticket table and a deploy you trust.

## Files

| File | What it does |
|---|---|
| `docs/AGENT_LOOP.md` | The charter: mission, kill switch, data sources, KPIs, the graded merge policy, what each run does and the report format. The agent's only instruction set. |
| `.claude/agents/pr-grader.md` | The grader. A frontmatter hook limits its Bash to `gh pr view` and `gh pr diff`. |
| `.claude/hooks/guard-bash.sh` | Blocks force pushes and pushes to main, so the agent works through PRs. |
| `.claude/settings.json` | Wires the guard with `onFailure: block`, so a broken hook stops the call instead of letting it through. Adds deny rules. |
| `scripts/run.sh` | Runs one loop with turn and budget caps, after checking the charter's pause line, and ends with the outcome check. |
| `bin/claude-run` | Drop-in for `claude -p`. Logs each run's exit, turns and cost to `$AGENT_OPS_DIR/runs.jsonl` (default `~/.agent-ops`). |
| `bin/ops-check` | Runs an outcome check and logs pass or fail to the same ledger. |
| `checks/report-landed.sh` | Example check: today's report landed, on main or its PR branch, with every section. Write one per loop; it's the only definition of "done" that doesn't trust the agent. |
| `bin/heartbeat.py` | Alerts through `$AGENT_OPS_NOTIFY` on a failed check, a silent loop or a run over 3x its usual cost, at most every 3 days per alert. Writes `COSTS.md`. |
| `scripts/night-summary.sh` | What merged, closed and escalated overnight, plus any reverts. |
| `scripts/loop-stats.sh` | Your track record as JSON: commits and merged PRs per month, reverts, escalations. Publish it. |
| `tests/` | Feeds known commands to both hooks, and fixture ledgers to `ops-check` and the heartbeat. |
| `examples/` | A crontab, cloud task prompts for the loop and the cloud watcher, a GitHub Actions workflow that grades in CI, and the support agent. |

## Limits, honestly

- The grader is the same model as the author. Its only independence is that it never saw the author's context. That's worth a lot, and it isn't a second opinion from a different mind.
- "Verified" for UI means the author rendered the page and attached a screenshot and console output. That evidence still comes from the author, and it's the weakest link.
- This has run on one product with one human. If you run it on a team, I'd like to hear what breaks.

MIT licensed. By [Albert Nahas](https://github.com/albertnahas).
