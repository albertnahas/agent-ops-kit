# Loop catalog

The loop types a product ends up needing, taken from the fleet that runs OpenWhen and a handful of side projects. `skills/plan-loops` reads a project and picks from this list. Start with the fewest loops that cover the product's real risks: one loop that runs well beats five that page you.

A loop is a trigger, one job written down as a charter (`docs/AGENT_LOOP.md`), an outcome check with no model in it, and a ledger line per run (`bin/claude-run`, `bin/ops-check`). Anything missing one of those isn't a loop yet. Daemons, dashboards and model-free watchers are services: they go in the registry's Services table, not its loop table.

**Checked by** is who reads a loop's output after its own check passes: another loop (daily ops grades the fix agent's PRs), a script (the heartbeat), or you. Every loop names one, because an output nobody checks is how a loop drifts. The fleet dashboard draws these links.

## Per product

| Loop | Needs it when | Trigger | Output | Outcome check | Checked by | Cost |
|---|---|---|---|---|---|---|
| **Daily ops** | it has users or revenue | daily, early | a report PR with metrics, anomalies and fixes; sweeps and grades open PRs | the report PR exists for today with every section | you, reading the report; grades by a fresh-context grader | $1–5 a run |
| **Smoke test** | it has a deploy that can break a journey | daily, before you wake | pass or fail per journey | the test runner's exit | heartbeat; daily ops reads failures | free (no model) |
| **Support desk** | strangers can email or chat you | on a ticket | a reply sent, or an escalation with a one-tap decision | the server checks every reply before it sends | you, on escalations; daily ops reads the ticket log | cents a ticket |
| **Fix on demand** | support escalates bugs | on "fix it" | a fix PR | the PR exists and CI is green | daily ops, which grades and merges | $1–3 a fix |
| **Incident** | it has an uptime probe | on an alert | a diagnosis in the incident row, a fix PR when obvious | the row has a diagnosis | you | $1–3 an incident |
| **Growth** | it needs traffic: SEO, pages, experiments | weekly | one shipped page or experiment as a PR, the last week's numbers | the PR exists and links its metric | daily ops grades it; strategy reads the numbers | $2–6 a run |
| **Social** | it has an audience channel | one to four sittings a day | posts and replies | each post reads back from the platform | you, weekly; the post's numbers | $0.5–2 a sitting |
| **Strategy** | it's past launch and earns or could | monthly | a memo of at most three bets, each with a 2-week test, a yes number and a kill rule | the memo has a ceiling, the bets and their read dates | you: approve, reject or defer by its deadline | $3–8 a run |

## Per person (the fleet itself)

| Loop | Needs it when | Trigger | Output | Outcome check | Checked by | Cost |
|---|---|---|---|---|---|---|
| **Heartbeat** | you run more than one loop | daily | alerts on failed, silent and costly loops; `COSTS.md` | its own liveness line | a cloud watch that alerts if the heartbeat goes quiet | free |
| **Cloud watch** | the heartbeat runs on a laptop | daily, in the cloud | an alert if the heartbeat stopped | the routine's run status | you | cents |
| **Master queue** | one-off work has no owning loop | daily | due queue items done, follow-ups added as new lines | the queue parses and nothing due is left untouched | you, through owner-you lines | $1–3 a run |
| **Fleet dashboard** | you can't name every loop from memory | twice a day (model-free build) | `fleet/dashboard.html`, optionally the claude.ai dashboard | the sync receipt matches the data | you | free; sync cents |
| **Radar** | you want to hear about jobs, events, papers or competitors | weekly | a digest with links | the digest was sent and has entries | you | $0.5–2 a run |

## Rules that came from running these

- **A check reads something the run didn't write.** "The report says it posted" is not a check; the post reading back from the platform is. A check that only reads the agent's own words passes on a run that lied.
- **A crash can look like success.** A Claude run that dies on a usage limit still says `subtype: success`; its exit code doesn't. `ops-check` fails when the loop's last ledger line is a crashed run.
- **Every runner names its loop** (`OPS_LOOP`). Unnamed runs can't be costed or alerted on.
- **Chronic failure:** a check failing 3 of its last 7 runs is broken, either the loop or the check. Fix one within a week; pause the loop if neither is fixed in two.
- **Nobody reads it:** a loop whose output hasn't changed a decision, a PR or a post in 30 days is retired.
- **Attention is the budget.** At most one message a day to you across the whole fleet. When it goes over, merge alerts or raise thresholds; don't add a loop that pings you.
- **What a customer waits on runs in the cloud.** A laptop sleeps and travels; support and publishing don't.
