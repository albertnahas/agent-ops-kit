#!/usr/bin/env bash
# Runs one loop. Point cron, launchd or CI at this file.
# The charter's status line is checked here, before Claude starts, so a pause holds
# even if the model would have misread it. The run is logged by bin/claude-run and
# judged by its outcome check, not by Claude's exit code.
set -uo pipefail
cd "$(dirname "$0")/.."
CHARTER="docs/AGENT_LOOP.md"
mkdir -p logs

if ! grep -q '^status: active' "$CHARTER"; then
  echo "$(date -u +%FT%TZ) paused by charter, not starting" >> logs/agent.log
  exit 0
fi

bin/claude-run -p "Read $CHARTER and run it." \
  --max-turns "${MAX_TURNS:-120}" \
  --max-budget-usd "${MAX_BUDGET_USD:-15}" \
  --permission-mode auto \
  --permission-prompts none \
  >> logs/agent.log 2>&1

bin/ops-check -- checks/report-landed.sh >> logs/agent.log
