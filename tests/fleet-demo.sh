#!/usr/bin/env bash
# Builds the fleet dashboard from an invented fleet of 30 loops: every status, a checker chain three deep, two loops
# that check each other, a checker the registry doesn't have and two loops nobody checks. For screenshots and proofs.
# Usage: tests/fleet-demo.sh [folder]   Prints the dashboard's path. Needs bash and python3.
set -euo pipefail
cd "$(dirname "$0")/.."
export AGENT_OPS_DIR=${1:-$(mktemp -d)}
mkdir -p "$AGENT_OPS_DIR/fleet"
echo "{\"launch_agents\": \"$AGENT_OPS_DIR/none\", \"refresh\": \"Demo data\"}" > "$AGENT_OPS_DIR/fleet.json"
# Most loops are cloud routines; two are desktop-app tasks, and one is a launchd job, which shows as paused (not loaded here).
runtime() { case $1 in fleet-sync|life-review) echo app;; app-beta) echo mac;; *) echo cloud;; esac; }
job() { case $(runtime "$1") in app) echo "task:$1";; mac) echo "com.demo.$1";; *) echo "routine:$1";; esac; }
day() { date -v-"$1"d +%FT0"$2":00:00 2>/dev/null || date -d "$1 days ago" +%FT0"$2":00:00; }

loops=(
  # loop|project|checked by|outcomes, oldest first (p pass, f fail, - none)|days since last run
  "shop-daily-ops|Shop|you|pppppppppp|0"
  "shop-support|Shop|shop-daily-ops, you|ppppppppp|0"
  "shop-support-fix|Shop|shop-daily-ops|ppfpp|1"
  "shop-e2e-smoke|Shop|heartbeat, shop-daily-ops|pppppppf|0"
  "shop-publish|Shop|heartbeat|pppppppppp|0"
  "shop-growth|Shop|shop-daily-ops, you|pppp|2"
  "shop-social-morning|Shop|you|ppfpfpfpp|0"
  "shop-social-evening|Shop|you|pppppp|0"
  "shop-reddit|Shop|you|ppppp|0"
  "shop-product|Shop|you|p|6"
  "blog-daily-ops|Blog|you|pppppp|0"
  "blog-writer|Blog|blog-editor|pppppp|0"
  "blog-editor|Blog|blog-daily-ops|pppppp|0"
  "blog-seo|Blog||pppp|0"
  "blog-links|Blog|you|pppppf|0"
  "app-daily-ops|Mobile app|you|ppppppp|0"
  "app-crash-triage|Mobile app|app-daily-ops|ppppp|0"
  "app-reviews|Mobile app|app-store-watch|ppppp|0"
  "app-store-watch|Mobile app|app-reviews|ppppp|0"
  "app-release-notes|Mobile app||-|0"
  "app-beta|Mobile app|you|ppp|5"
  "heartbeat|Ops|uptime-pager|pppppppppp|0"
  "master|Ops|you|pppppppppp|0"
  "vault-sync|Ops|heartbeat|pppppppppp|0"
  "fleet-sync|Ops|you|ppppp|0"
  "news-radar|Personal|you|pppppp|0"
  "job-watch|Personal|you|ppppp|0"
  "events-radar|Personal|you|pppp|0"
  "reading-list||you|ppp|0"
  "life-review|Personal|you|-|0"
)
{
  printf '## Registry\n\n| Loop | Project | Runtime | Job | Schedule | Charter | Outcome check | Checked by |\n|---|---|---|---|---|---|---|---|\n'
  for l in "${loops[@]}"; do IFS='|' read -r name project by _ _ <<< "$l"; echo "| $name | $project | $(runtime "$name") | $(job "$name") | daily | | | $by |"; done
  printf '\n## Services\n\n| Service | Job | What it is |\n|---|---|---|\n| Fleet build | com.demo.fleet-build | rebuilds the dashboard |\n'
} > "$AGENT_OPS_DIR/REGISTRY.md"
{
  for l in "${loops[@]}"; do
    IFS='|' read -r name _ _ hist ago <<< "$l"
    [ "$hist" = - ] && continue
    for ((i = 0; i < ${#hist}; i++)); do
      c=${hist:i:1}; d=$((ago + ${#hist} - 1 - i))
      echo "{\"loop\":\"$name\",\"date\":\"$(day "$d" 6)\",\"subtype\":\"success\",\"cost\":0.4$((i % 10))}"
      echo "{\"loop\":\"$name\",\"date\":\"$(day "$d" 7)\",\"check\":\"$([ "$c" = p ] && echo pass || echo fail)\",\"detail\":\"$([ "$c" = p ] && echo 'report landed' || echo 'report missing')\"}"
    done
  done
  echo "{\"loop\":\"stray-script\",\"date\":\"$(day 1 6)\",\"subtype\":\"success\"}"
} > "$AGENT_OPS_DIR/runs.jsonl"
routines=$(for l in "${loops[@]}"; do IFS='|' read -r name _ _ _ _ <<< "$l"; [ "$(runtime "$name")" = cloud ] || continue
  printf '{"name":"%s","enabled":true,"cron":"0 6 * * *","next_run_at":null,"last_status":null,"last_finished_at":null},' "$name"; done)
tasks=$(for l in "${loops[@]}"; do IFS='|' read -r name _ _ _ _ <<< "$l"; [ "$(runtime "$name")" = app ] || continue
  printf '{"id":"%s","enabled":true,"cron":"0 6 * * *","next_run_at":null,"last_finished_at":null},' "$name"; done)
echo "{\"at\":\"$(date +%FT%T%z | sed 's/\(..\)$/:\1/')\",\"routines\":[${routines%,}],\"tasks\":[${tasks%,}]}" > "$AGENT_OPS_DIR/fleet/cloud.json"
python3 fleet/fleet.py >/dev/null
echo "$AGENT_OPS_DIR/fleet/dashboard.html"
