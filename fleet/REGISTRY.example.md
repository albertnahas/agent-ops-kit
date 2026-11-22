# Loop registry

Every scheduled loop you run, one row each. `fleet/fleet.py` reads the two tables below by their headings, so keep the column names. A loop that isn't here doesn't exist as far as the fleet is concerned, and the dashboard shows any running job with no row as Unregistered.

- **Loop** is the name it logs under (`OPS_LOOP`); for a cloud routine that doesn't log, the routine's name. A check script at `<checks>/<Loop>.py` is run by the builder when the loop writes no ledger line.
- **Job** is what triggers it: a launchd label, `cron:<script name>` (a crontab line), `routine:<name>` (Claude Code cloud routine) or `task:<id>` (desktop-app scheduled task).
- **Schedule** is for people. A cron in backticks overrides the job's own trigger, for runners that skip some fires. In an override, a day of month and a weekday must both match (`0 8 1-7 * 1` is the first Monday); crontab itself fires on either.
- **Checked by** is who reads its output after its check passes: other loops by name, `heartbeat`, or `you`, comma-separated. `docs/LOOP_CATALOG.md` says who usually does for each kind of loop.
- **Project** groups the dashboard; leave it empty for loops that serve no one project (they show under General).

## Registry

| Loop | Project | Runtime | Job | Schedule | Charter | Outcome check | Checked by |
|---|---|---|---|---|---|---|---|
| myapp-daily-ops | MyApp | cloud | routine:myapp-daily-ops | daily 06:00 | `myapp/docs/AGENT_LOOP.md` | report PR for today (`checks/myapp-daily-ops.py`) | you |
| myapp-smoke | MyApp | mac | com.me.myapp-smoke | daily 05:30 | `myapp/e2e/` | the tests | heartbeat, myapp-daily-ops |
| heartbeat |  | mac | com.me.heartbeat | daily 09:30 | `bin/heartbeat.py` | its own liveness line | you |

## Services

Daemons, dashboards and model-free watchers: they run, but they aren't loops.

| Service | Job | What it is |
|---|---|---|
| Fleet dashboard build | com.me.fleet-build | rebuilds `fleet/dashboard.html` every 30 minutes, no model |
