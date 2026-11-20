#!/usr/bin/env bash
# Checks the run ledger: ops-check logs pass and fail, and the heartbeat alerts on a failed
# check, a silent loop and a costly run, and stays quiet on a healthy one.
# Usage: tests/ops.test.sh   Needs bash, jq and python3. Writes only to a temp folder.
set -uo pipefail
cd "$(dirname "$0")/.."
export AGENT_OPS_DIR=$(mktemp -d) AGENT_OPS_NOTIFY=true
trap 'rm -rf "$AGENT_OPS_DIR"' EXIT
fail=0
expect() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }

bin/ops-check -l good -- true >/dev/null
bin/ops-check -l broken -- sh -c 'echo report missing; exit 1' >/dev/null
expect "ops-check passes through the exit code" "! bin/ops-check -l broken -- false >/dev/null"
expect "ops-check logs pass and fail" "[ \$(grep -c '\"check\":\"pass\"' $AGENT_OPS_DIR/runs.jsonl) = 1 ] && grep -q 'report missing' $AGENT_OPS_DIR/runs.jsonl"

day() { date -v-"$1"d +%FT10:00:00 2>/dev/null || date -d "$1 days ago" +%FT10:00:00; }
for d in 12 11 10 9; do echo "{\"loop\":\"quiet\",\"date\":\"$(day $d)\",\"subtype\":\"success\",\"cost\":1}"; done >> "$AGENT_OPS_DIR/runs.jsonl"
for d in 6 5 4 3 2 1; do echo "{\"loop\":\"pricey\",\"date\":\"$(day $d)\",\"subtype\":\"success\",\"cost\":1}"; done >> "$AGENT_OPS_DIR/runs.jsonl"
echo "{\"loop\":\"pricey\",\"date\":\"$(day 0)\",\"subtype\":\"success\",\"cost\":9}" >> "$AGENT_OPS_DIR/runs.jsonl"

echo 'not json' >> "$AGENT_OPS_DIR/runs.jsonl"

out=$(bin/heartbeat.py | tail -1)
expect "heartbeat flags the failed check" "jq -e '.alerts | any(startswith(\"check:broken\"))' <<<'$out' >/dev/null"
expect "heartbeat flags the silent loop" "jq -e '.alerts | index(\"silent:quiet\")' <<<'$out' >/dev/null"
expect "heartbeat flags the costly run" "jq -e '.alerts | any(startswith(\"cost:pricey\"))' <<<'$out' >/dev/null"
expect "heartbeat leaves the healthy loop alone" "! jq -e '.alerts | any(contains(\"good\"))' <<<'$out' >/dev/null"
expect "heartbeat flags a malformed ledger line and keeps going" "jq -e '.alerts | any(startswith(\"ledger:\"))' <<<'$out' >/dev/null"
expect "heartbeat writes COSTS.md" "grep -q '| pricey | 7 | 0 | \\\$15.00' $AGENT_OPS_DIR/COSTS.md"
expect "heartbeat logs its own pass line" "tail -1 $AGENT_OPS_DIR/runs.jsonl | grep -q '\"loop\": \"heartbeat\"'"
expect "an alert is sent once, then held for 3 days" "[ \"\$(bin/heartbeat.py | tail -1 | jq -c .sent)\" = '[]' ]"

exit $fail
