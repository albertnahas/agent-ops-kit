# <Project> Agent Loop: Charter

status: active

<!-- Set `status: paused` and push to stop the loop. The runner checks this line before Claude starts, and the agent checks it again first thing. -->

Single source of truth for the scheduled agent. It overrides the routine's prompt. Steer the loop by editing this file, never the routine.

## Mission

<One or two sentences: what the agent operates, what "better" means, and what it must never trade away for it.>

## Kill switch

1. **Pause:** set `status: paused` above and push to main.
2. **Hard stop:** <the exact command, e.g. disable the scheduled task at claude.ai/code/routines, `launchctl unload ~/Library/LaunchAgents/<label>.plist`, or disable the workflow in GitHub>.

## Data sources

Read-only. For each source: how to read it, and its quirks (row caps, time zones, what counts as an event).

- <source>: <how> - <quirk>

If a source fails, write a report that says so and stop. Never change code blind. A slow probe is not an outage on its own: check whether real activity is still landing before you call one.

## KPIs

| KPI | Baseline (reference period) | Alert if |
|---|---|---|
| <metric> | <value> (<dates>) | <threshold, e.g. below X for 2+ days> |

Never lower a baseline to match a worse run, or a stall reads green. Any KPI down more than 20% week over week leads the report. Check the comparison week wasn't a holiday or a launch spike first.

## Merge policy (graded)

Every PR is graded by an independent reviewer: the `pr-grader` subagent, with fresh context, reading only this section, the PR body and the diff. It judges the code, not the author's reasoning. A human sees only grade X. The run posts the reviewer's grade on every PR, not only X, as a PR comment starting `**Grade: <letter>**`, labels the PR `grade:<letter>` (dropping any older grade label) and ends its body with a `## Grade` section: the letter, the reviewer's one-line verdict and a link to that comment. A regrade replaces both, so the label and the body always show the latest grade.

- **A, merge.** Correct, verified, fully undone by a revert. Squash-merge.
- **B, fix then merge.** Real but fixable findings: a bug, a console error, a visual flaw, a stale assumption. Fix on the branch, verify, grade again, merge. Never park a PR on a B.
- **C, close.** Superseded or moot. Close with a comment naming the commit or reason.
- **X, human.** Hard to undo. Leave open with the label `founder`, the grader's findings as a PR comment, and one line under Escalations.

X means a revert won't fully undo it:

- money movement: checkout, webhooks, purchases, prices, refunds
- migrations that rewrite or drop data
- user identity, auth and secrets
- new dependencies
- paid-API spend
- deleting user data
- this file's merge policy, the grader, the hooks and CI workflows
- <your own surfaces>

Not X, so grade A, B or C: copy, UI, seasonal looks, product limits, admin and analytics pages, the rest of this charter. <Add yours.>

**Verified** means lint, typecheck, build and tests pass, the deploy preview is green, and anything that renders was rendered at phone width and looked at, with a clean console. Tests pass while artwork is hidden or hydration fails, so a UI change without a screenshot and console output in the PR is a B at most. A PR that changes something a user sees also uploads a phone-width video of that journey, recorded with Playwright from test data only, as `pr-<number>-<journey>.mp4` on the repo's `proofs` pre-release, and links it in the PR body; the reviewer grades a PR without one B. Record with `video: 'on'` on an iPhone viewport, convert with `ffmpeg -i in.webm -pix_fmt yuv420p -movflags +faststart out.mp4`, then `gh release upload proofs <file> --clobber` (create it once with `gh release create proofs --prerelease --notes 'PR proof videos'`).

## Each run

1. Check `status:` above. If it isn't `active`, stop.
2. Read the last 3 reports in `docs/ops-reports/`. They are your memory.
3. **PR sweep, before new work.** For every open PR, whatever its author: rebase on main keeping both sides of a conflict, grade it with `pr-grader`, act on the grade. Merging deploys, so merge one at a time and rebase the next on the result. Only X stays open; an X open more than 14 days leads the report.
4. Pull today's data. Rank findings by the KPI table.
5. New work: at most 2 PRs, each small and focused, each traced to a number in today's data. No refactors for taste. One change at a time per surface.
6. Write the report and land it as a report-only PR.

## Report

`docs/ops-reports/YYYY-MM-DD.md`. Delete reports older than the last 3 in the same commit (git keeps them). Hard cap: 80 lines, no line over about 300 characters. State each number once.

1. **TLDR:** at most 3 bullets.
2. **KPIs:** one table: KPI | today | baseline | 7-day trend | status.
3. **Findings:** ranked, max 5, each with its evidence and a proposed action.
4. **Actions taken:** PRs opened, merged, closed or left open, each with its grade.
5. **Escalations:** a ledger, one line each: `n. issue - first raised YYYY-MM-DD - recommendation - cost`. Carry items forward until marked `RESOLVED - <how>` or `DECIDED - <what>`.
6. **Handoff:** what tomorrow's run should check.

Decided questions go in one line in `docs/DECISIONS.md`. Don't relitigate anything listed there.

## Operating principles

- Data first: every action traces to a number in today's pull.
- Prefer small reversible changes over big ones.
- When unsure whether something is X, it's X.
