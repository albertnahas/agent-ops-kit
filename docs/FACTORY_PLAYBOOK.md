# Software factory playbook

A software factory here means scheduled Claude Code loops that run your products while you're doing something else, and a short set of rules for which loops get to exist. This page gives the order to set things up and the rules for when a loop is born, fixed or retired, what it may cost and when it may bother you. Each part links to the file that owns the detail. Read this first, then follow the links.

To have Claude walk you through it for a project, ask it to "start a software factory for this project" (the `factory` skill).

## What a loop is

A trigger, one job written down as a charter, an outcome check with no model in it, and a ledger line per run. If one of those is missing, it isn't a loop yet. The full definition, and the line between loops and services, is at the top of [LOOP_CATALOG.md](LOOP_CATALOG.md).

## Start in this order

Build the factory from the watchman outward. A loop you can't see fail is worse than no loop.

1. **The watchman.** Copy the kit in and run its tests ([README, "Try it in 5 minutes"](../README.md#try-it-in-5-minutes)). Every Claude call goes through `bin/claude-run`, every run ends with `bin/ops-check`, and `bin/heartbeat.py` runs daily. If the heartbeat lives on a laptop, add the cloud watch from [examples/heartbeat-watch-prompt.md](../examples/heartbeat-watch-prompt.md).
2. **Daily ops on one product.** One charter from [AGENT_LOOP.md](AGENT_LOOP.md) with your own X surfaces, and the PR grader. Run it by hand, then on a schedule. For the first week, read every report and every grade before you trust them.
3. **A smoke test**, once a deploy can break a journey. It needs no model and costs nothing.
4. **The fleet dashboard and registry**, as soon as you run more than one loop ([fleet/](../fleet/README.md), the `fleet` skill).
5. **Support desk and fix on demand**, once strangers write to you and you trust your deploy ([examples/support-agent/](../examples/support-agent/README.md)).
6. **Growth, social and strategy**, after launch, each when its "needs it when" holds in the catalog.

The `plan-loops` skill reads a project and proposes loops from [LOOP_CATALOG.md](LOOP_CATALOG.md) in this spirit: the fewest that cover the real risks, usually one to three per project.

## The registry and outcome checks

Every loop has a row in one registry, added in the same change that schedules it. A loop that isn't in the registry doesn't exist, and the dashboard shows any running job without a row as Unregistered. The columns and what goes in each are in [fleet/REGISTRY.example.md](../fleet/REGISTRY.example.md).

**Checked by** is the column people skip, and the one that matters most. It names who reads a loop's output after its own check passes: another loop, the heartbeat, or you. An output nobody checks is how a loop drifts. The catalog says who usually checks each kind of loop.

Write the outcome check before the prompt. If you can't say what proves the run did its job, the loop isn't ready. The check reads something the run didn't write: the PR exists, the post reads back from the platform, the report has every section. Success is the check passing, not Claude's exit code. [checks/report-landed.sh](../checks/report-landed.sh) is a worked example, and the "Rules that came from running these" in the catalog say why.

Every runner exports `OPS_LOOP=<registry name>`, so the ledger, the heartbeat and the dashboard all agree on which loop is which. `plan-loops` builds each new loop in this order: charter, check, runner, hand run, schedule, registry row.

## Budgets

Two budgets, and the second runs out first.

**Money.** Every Claude call carries `--max-turns` and `--max-budget-usd` ([scripts/run.sh](../scripts/run.sh) sets both). The heartbeat alerts on a run over 3x that loop's median and writes `COSTS.md`. Read that table weekly. Set a weekly ceiling per loop, and give any loop above it one line in its charter saying why it's worth the money. `COSTS.md` only knows Claude's cost. Paid APIs your loops call aren't in it.

**Your attention.** Aim for at most one message a day from the whole fleet. A loop messages you only when it's blocked on you, and both of these are true:
- the next step needs you: your login, your money, your identity, a decision only you make, or something physical;
- waiting costs something: a due date, money, an account, a loop that stops.

Anything else goes in a report or on the dashboard's waiting list, where you read it when you choose. When the fleet goes over budget, merge alerts or raise thresholds. Don't add a loop that pings you.

## Fix or retire

The two health rules live in the catalog: a check failing 3 of its last 7 runs is broken and gets fixed within a week or paused within two, and a loop whose output hasn't changed a decision, a PR or a post in 30 days is retired. The dashboard marks the first as Flaky. Nothing marks the second for you, so look for it.

Retiring is real removal: stop the schedule, delete the registry row, keep the charter in git, and write down why in one line. The `fleet` skill does it on your yes ("Retire a loop" in [skills/fleet/SKILL.md](../skills/fleet/SKILL.md)).

Once a month, go through the fleet loop by loop: runs, failed checks, cost from `COSTS.md`, and the last time its output mattered. Decide what to retire, merge, or move to the cloud. The kit gives you the numbers, but the decision is yours.

## When work earns its own loop

**A project** earns its first loop when it has users or revenue. That's when daily ops' "needs it when" holds. Before that, it needs no loop.

**A kind of work** earns a loop when the same task shows up three times in 30 days. Until then, it goes in a master queue: one file for every one-off with no owning loop.

```
# Queue
due | kind | item | owner | next action | done when | source
2026-12-01 | check | Renew the support inbox domain | You | pay the renewal | domain shows the new expiry | agent
```

After the two header lines, it's one line per item with seven fields, so the dashboard can read it. Point `waiting.queue` in `fleet.json` at the file, and every line with your name as owner shows up on the waiting list. A daily master run works through the queue:
- It does the items that are due and owned by the master.
- It turns each follow-up it finds into a new dated line.
- It moves each finished item to a done log as a single line, and that log is where you count the "three in 30 days".
- It keeps the queue under 30 open items.
- Queue lines are tasks, not permission. The master never does an X-class action from the queue. It sets the owner to you and writes down exactly what you need to do.

The kit doesn't ship a master charter. Write one from these rules.

## Big changes are bets

Small changes ship through the loops and the merge policy. Anything that changes what a product is, who it's for or who pays is a bet, and every bet goes through the same path.

**Where bets come from.** Each product past launch gets one monthly strategy loop (in the catalog). It proposes at most three bets in a memo and does nothing else. Pages, copy and single-screen tests belong to the ops and growth loops. A bet you think up in a session goes into the next memo, not straight into code.

**What a bet carries.**
- The arithmetic: which term of the revenue equation it moves, from what to what.
- Every rate either linked to a comparable or named as the riskiest assumption.
- Outside evidence, with links and dates.
- The cheapest test of that assumption, run within 14 days of approval.
- A yes number and a kill rule, both written down before the test starts, and a read date.

The test measures demand directly, with signups, replies or pre-orders, because at small volumes you can't read conversion in two weeks. A fake door can be the test. It's never the bet.

**Your part.** Approve, reject or defer each bet in the memo's "Founder decisions" section by its deadline. The dashboard lists open decision sections from your repos' `docs/` (`waiting.github.memo_roots` in `fleet.json`). Silence means undecided: the bet is carried to the next memo, never assumed approved. A bet that reopens a settled decision says which one and what's different this time.

**After you decide.** An approved bet's test is filed the same day, as a queue line or in the owning loop's charter, and only the test gets built. On the read date, the next memo reports the number against the kill rule. A killed bet goes into [DECISIONS.md](DECISIONS.md) so it isn't proposed again in the same form. A bet that clears comes back with its next, bigger test. Only once the evidence is strong enough does it get built, as normal graded PRs, with money, identity and data surfaces still X.

Example of one bet in a memo (an imaginary product):

```
### Bet 2: sell team plans to wedding planners
Moves: payers per month, 40 to 400, if 1 in 20 planners we reach buys.
Riskiest assumption: planners buy for clients (no comparable found).
Evidence: two planner forums asking for bulk cards (links, Oct 2026).
Test: email 200 planners an offer page with a pre-order button, by 6 Dec.
Yes: 10 pre-orders. Kill: under 3. Read: 20 Dec.
Founder decision: approve / reject / defer by 1 Dec.
```

## Scaling

What breaks first as the fleet grows, in the order it hurts:

1. **Names.** The ledger is only as good as its loop names. A runner without `OPS_LOOP` logs under its repo's folder name, so two loops in one repo get counted as one.
2. **One laptop.** Everything local stops when the laptop sleeps or travels. Anything a customer waits on, like support or publishing, moves to the cloud first.
3. **Lists kept by hand.** The registry is the only list. Anything else that names loops, like an alert's allowlist or a script's prefix list, goes stale.
4. **Attention.** More loops mean more messages. The attention budget is the real limit, not the number of loops.
5. **Shared rules.** Every charter carries a copy of the merge policy. Past about five repos, move it into one file that every repo reads from main.
