# agent-ops-kit

The setup I use to let a scheduled Claude Code agent open, grade and merge PRs on a live product while I sleep. Copy it into your repo, fill in the charter, and run it.

On [OpenWhen](https://www.openwhen.cards), a product I built and run alone, this setup has merged 157 PRs since July 2026. 114 came from the scheduled loop and the rest from Claude Code sessions I directed. One was reverted. The full numbers, with the method, are at [nightshiftdev.xyz/log](https://nightshiftdev.xyz/log).

## What's in it

| File | What it does |
|---|---|
| `docs/AGENT_LOOP.md` | The charter: mission, kill switch, data sources, KPIs, the graded merge policy, what each run does and the report format. The agent's only instruction set. |
| `.claude/agents/pr-grader.md` | The independent reviewer. Fresh context, reads only the merge policy, the PR body and the diff. A frontmatter hook limits its Bash to `gh pr view` and `gh pr diff`. |
| `.claude/hooks/guard-bash.sh` | Blocks force pushes and pushes to main, so the agent works through PRs. |
| `.claude/settings.json` | Wires the guard with `onFailure: block`, so a broken hook stops the call instead of letting it through. Adds deny rules. |
| `scripts/run.sh` | Runs one loop with turn and budget caps. Checks the charter's pause line before Claude starts. |
| `scripts/night-summary.sh` | What merged, closed and escalated overnight, plus any reverts. |
| `scripts/loop-stats.sh` | Your track record as JSON. Publish it. |
| `tests/hooks.test.sh` | Feeds known commands to both hooks and checks what they block. |
| `examples/` | A crontab line, a cloud scheduled task prompt, and a GitHub Actions workflow that grades in CI. |

## How the grading works

Every PR gets one of four grades from a reviewer that never saw the author's reasoning:

- **A:** correct, verified and fully undone by a revert. It merges.
- **B:** a fixable problem. The loop fixes it on the branch, grades again, merges.
- **C:** superseded. It gets closed with a reason.
- **X:** a revert won't fully undo it (money, data-destroying migrations, auth, secrets, new dependencies, paid API spend, deleting user data, the policy itself). It gets the `founder` label and waits for a human.

The test for X is "hard to undo", not "important". The charter also lists what isn't X. Without that list a careful grader escalates everything, and the real escalations drown.

## Setup

1. Copy `.claude/`, `docs/`, `scripts/` and `tests/` into your repo.
2. Fill in every `<placeholder>` in `docs/AGENT_LOOP.md`. Add your own X surfaces.
3. Run `tests/hooks.test.sh`. Everything should say `ok`.
4. On GitHub: create a `founder` label, turn on delete-branch-on-merge, and protect main if your plan allows it. The guard hook is a speed bump. Branch protection is the wall.
5. Schedule `scripts/run.sh` (see `examples/crontab`), or create a cloud scheduled task with the prompt in `examples/cloud-task-prompt.md`.
6. Watch the first week. Read every report and every grade before you trust it.

Needs Claude Code v2.1.295 or later (for `onFailure`), plus `gh` and `jq`.

## Limits, honestly

- The grader is the same model as the author. Its only independence is that it never saw the author's context. That's worth a lot, and it isn't a second opinion from a different mind.
- "Verified" for UI means the author rendered the page and attached a screenshot and console output. That evidence still comes from the author, and it's the weakest link.
- This has run on one product with one human. If you run it on a team, I'd like to hear what breaks.

## Guides

The reasoning behind each piece, with the incidents that shaped it:

- [Agent charter](https://nightshiftdev.xyz/guides/agent-charter)
- [AI PR review and auto-merge](https://nightshiftdev.xyz/guides/ai-pr-review-auto-merge)
- [Claude Code hooks](https://nightshiftdev.xyz/guides/claude-code-hooks)
- [Run Claude Code on a schedule](https://nightshiftdev.xyz/guides/run-claude-code-on-a-schedule)

MIT licensed. By [Albert Nahas](https://nightshiftdev.xyz).
