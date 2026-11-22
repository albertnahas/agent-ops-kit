#!/usr/bin/env bash
# Runs the {{name}} loop once. Written by new-loop; launchd or cron points at this file.
# The charter's status line is checked before Claude starts, so a pause holds even if the
# model would misread it. The run is judged by its outcome check, not Claude's exit code.
set -uo pipefail
cd {{repo}} || exit 1
export OPS_LOOP={{name}}
charter={{charter}} log={{log}}
mkdir -p "$(dirname "$log")"

if ! grep -q '^status: active' "$charter"; then
  echo "$(date +%FT%T%z) paused by charter, not starting" >> "$log"
  exit 0
fi

bin/claude-run -p "Read $charter and run it." \
  --max-turns {{turns}} \
  --max-budget-usd {{budget}} \
  --permission-mode auto \
  --permission-prompts none \
  >> "$log" 2>&1

bin/ops-check -- python3 {{check}} >> "$log"
