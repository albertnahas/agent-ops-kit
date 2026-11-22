# Where a loop runs

Go down this list and stop at the first line that fits.

1. **It needs no judgement.** Then it isn't an agent. Make it a plain script on cron, launchd, pg_cron or the host's cron.
2. **A customer, money or a deadline waits on it, or it has to run while the laptop sleeps or travels.** Cloud routine. If the work starts from an event in the database, a db trigger (pg_cron) starts the routine.
3. **It needs this machine:** files outside git, a logged-in browser or session, local secrets, the vault, launchctl, hardware. Mac: launchd, or cron on Linux.
4. **It needs the desktop app's own tools:** computer use, the app's connectors, the session list. App task, and only for work that can wait, because it runs only while the app is open.
5. **Anything else.** Mac if it wakes often and usually finds nothing to do, because a free shell gate can call Claude only when there's work. Cloud if it only needs the repo and runs at most once a day.

| Runtime | Always on | Sees | Free gate before Claude | Reaches the ledger by |
|---|---|---|---|---|
| Plain script | while its host is | its host | it is the gate | `ops-check` in the same crontab line |
| Cloud routine | yes | the repo and the routine's own secrets | no, every run is a Claude run | a local `ops-check` of its outcome after it, or fleet-sync recording its run status |
| Mac (launchd, cron) | only while the machine is awake | this machine's files, sessions and secrets | yes, the runner can exit before `claude-run` | `claude-run` and `ops-check` in its runner |
| App task | only while the desktop app is open | this machine, plus the app's tools | no | a local `ops-check` of its outcome after it, or fleet-sync recording its run status |

**Every runtime leaves a ledger line the heartbeat reads.** A loop the heartbeat can't see fails silently. A routine's final message saying "report done" isn't a check: something with no model in it has to read the outcome and write the line.

`/agent-ops-kit:new-loop` asks the runtime question from this page, and `bin/new-loop` writes launchd, cron, cloud and app loops. A plain script needs neither.
