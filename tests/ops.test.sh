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

printf 'not json\n{}\n' >> "$AGENT_OPS_DIR/runs.jsonl"
stub="$AGENT_OPS_DIR/stub"; mkdir "$stub"; printf '#!/bin/sh\necho auth failed >&2; exit 1\n' > "$stub/claude"; chmod +x "$stub/claude"
PATH="$stub:$PATH" OPS_LOOP=crashed bin/claude-run -p hi >/dev/null 2>&1
expect "claude-run logs a run that printed nothing" "grep -q '\"loop\":\"crashed\".*\"subtype\":\"no_json\"' $AGENT_OPS_DIR/runs.jsonl"

out=$(bin/heartbeat.py | tail -1)
expect "heartbeat flags the failed check" "jq -e '.alerts | any(startswith(\"check:broken\"))' <<<'$out' >/dev/null"
expect "heartbeat flags the silent loop" "jq -e '.alerts | index(\"silent:quiet\")' <<<'$out' >/dev/null"
expect "heartbeat flags the costly run" "jq -e '.alerts | any(startswith(\"cost:pricey\"))' <<<'$out' >/dev/null"
expect "heartbeat leaves the healthy loop alone" "! jq -e '.alerts | any(contains(\"good\"))' <<<'$out' >/dev/null"
expect "heartbeat flags malformed ledger lines and keeps going" "jq -e '[.alerts[] | select(startswith(\"ledger:\"))] | length == 2' <<<'$out' >/dev/null"
expect "heartbeat writes COSTS.md" "grep -q '| pricey | 7 | 0 | \\\$15.00' $AGENT_OPS_DIR/COSTS.md"
expect "heartbeat logs its own pass line" "tail -1 $AGENT_OPS_DIR/runs.jsonl | grep -q '\"loop\": \"heartbeat\"'"
expect "an alert is sent once, then held for 3 days" "[ \"\$(bin/heartbeat.py | tail -1 | jq -c .sent)\" = '[]' ]"

# mission-guard: bless, clean check, then a pushed edit to a marked block drifts
g=$(mktemp -d); git init -q --bare "$g/origin.git"; git clone -q "$g/origin.git" "$g/w" 2>/dev/null
printf '# C\n<!-- mission -->\nNever lower a baseline.\n<!-- /mission -->\nsteps\n' > "$g/w/C.md"
git -C "$g/w" add . && git -C "$g/w" -c user.name=t -c user.email=t@t commit -qm c && git -C "$g/w" push -q origin HEAD:main
printf 'plain\n' > "$g/w/N.md"
expect "mission-guard refuses a file with no blocks" "! bin/mission-guard bless $g/w/N.md 2>/dev/null"
bin/mission-guard bless "$g/w/C.md" >/dev/null
expect "mission-guard check is clean after bless" "bin/mission-guard check | grep -q '^1 charters clean'"
sed -i.bak 's/Never lower/Always lower/' "$g/w/C.md" && rm "$g/w/C.md.bak"
expect "mission-guard ignores an unpushed edit" "bin/mission-guard check >/dev/null"
git -C "$g/w" -c user.name=t -c user.email=t@t commit -qam edit && git -C "$g/w" push -q origin HEAD:main
expect "mission-guard fails on a pushed edit to a block" "! bin/mission-guard check >/dev/null"
out=$(bin/heartbeat.py | tail -1)
expect "heartbeat alerts on mission drift" "jq -e '.alerts | index(\"mission:drift\")' <<<'$out' >/dev/null"
rm -rf "$g"

exit $fail
