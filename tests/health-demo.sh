#!/usr/bin/env bash
# Builds the loop-health page from an invented machine with no registry and no ledger: launchd jobs that ran, failed,
# went quiet, keep running or run once, crontab lines with and without an output file, a vendor's job, an unloaded
# one, and two cloud routines. Stand-ins for launchctl and crontab answer from the folder, so nothing real is read.
# Usage: tests/health-demo.sh [folder]   Prints the dashboard's path. Needs bash and python3.
set -euo pipefail
cd "$(dirname "$0")/.."
export AGENT_OPS_DIR=${1:-$(mktemp -d)}
D=$AGENT_OPS_DIR
mkdir -p "$D/bin" "$D/agents" "$D/launchctl" "$D/logs" "$D/fleet"
echo "{\"launch_agents\": \"$D/agents\", \"refresh\": \"Demo data\"}" > "$D/fleet.json"

cat > "$D/bin/launchctl" <<EOF
#!/usr/bin/env bash
[ "\$1" = list ] && [ -f "$D/launchctl/\$2" ] && cat "$D/launchctl/\$2"
EOF
cat > "$D/bin/crontab" <<EOF
#!/usr/bin/env bash
cat "$D/crontab"
EOF
chmod +x "$D/bin/launchctl" "$D/bin/crontab"

ago() { python3 -c "import time, os; t = time.time() - $2 * 3600; os.utime('$1', (t, t))"; }
h=$((10#$(date +%H))); digest=$(( h >= 7 ? h - 7 : h + 17 ))  # hours since the morning digest's last 07:00
# label|schedule plist keys (an old log is no proof a job stopped: it shows as ran, last run unknown)|last exit (none: not loaded; run: running now)|hours since its log changed
jobs=(
  "com.example.morning-digest|<key>StartCalendarInterval</key><dict><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>|0|$digest"
  "com.example.inbox-triage|<key>StartInterval</key><integer>1800</integer>|0|0.3"
  "com.example.price-watch|<key>StartCalendarInterval</key><dict><key>Minute</key><integer>15</integer></dict>|1|0.5"
  "com.example.weekly-review|<key>StartCalendarInterval</key><dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>|0|400"
  "com.example.notes-sync|<key>KeepAlive</key><true/>|run|"
  "com.example.launch-reminder|<key>StartCalendarInterval</key><dict><key>Month</key><integer>12</integer><key>Day</key><integer>24</integer><key>Hour</key><integer>9</integer></dict>|0|"
  "com.example.old-experiment|<key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer></dict>|none|"
)
for j in "${jobs[@]}"; do
  IFS='|' read -r label keys code hours <<<"$j"
  log=""
  if [ -n "$hours" ]; then log="<key>StandardOutPath</key><string>$D/logs/$label.log</string>"; : > "$D/logs/$label.log"; ago "$D/logs/$label.log" "$hours"; fi
  cat > "$D/agents/$label.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>/usr/local/bin/$label</string></array>$keys$log</dict></plist>
EOF
  case $code in
    none) ;;
    run) printf '{\n\t"PID" = 4242;\n\t"LastExitStatus" = 0;\n};\n' > "$D/launchctl/$label" ;;
    *) printf '{\n\t"LastExitStatus" = %s;\n};\n' "$code" > "$D/launchctl/$label" ;;
  esac
done
cat > "$D/agents/com.vendor.updater.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Label</key><string>com.vendor.updater</string>
<key>ProgramArguments</key><array><string>/Applications/Vendor.app/Contents/MacOS/updater</string></array><key>StartInterval</key><integer>3600</integer></dict></plist>
EOF
printf '{\n\t"LastExitStatus" = 0;\n};\n' > "$D/launchctl/com.vendor.updater"

: > "$D/logs/backup.log"; ago "$D/logs/backup.log" 2
cat > "$D/crontab" <<EOF
# m h dom mon dow command
MAILTO=""
0 */4 * * * cd $D && ./backup.sh >> $D/logs/backup.log 2>&1
@hourly /usr/bin/python3 $D/feed-poller.py
30 2 * * * /bin/bash -lc $D/never-ran.sh >> $D/logs/never-ran.log 2>&1
@reboot $D/on-boot.sh
EOF

iso() { python3 -c "import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(hours=$1)).isoformat(timespec='seconds'))"; }
cat > "$D/fleet/cloud.json" <<EOF
{"at": "$(iso 0)", "routines": [
 {"name": "repo-dependency-check", "enabled": true, "cron": "0 8 * * *", "next_run_at": null, "last_status": "succeeded", "last_finished_at": "$(iso 3)"},
 {"name": "release-notes-draft", "enabled": true, "cron": "0 17 * * 5", "next_run_at": null, "last_status": "failed", "last_finished_at": "$(iso 30)"},
 {"name": "competitor-digest", "enabled": true, "cron": "0 6 * * *", "next_run_at": null, "last_status": "succeeded", "last_finished_at": "$(iso 80)"},
 {"name": "paused-idea", "enabled": false, "cron": "0 9 * * *", "next_run_at": null, "last_status": null, "last_finished_at": null}],
 "tasks": []}
EOF

PATH="$D/bin:$PATH" python3 fleet/fleet.py >/dev/null
echo "$D/fleet/dashboard.html"
