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

# mission-guard: bless what's on the default branch (master here, to prove it isn't assumed), then catch drift
g=$(mktemp -d); git init -q --bare -b master "$g/origin.git"; git clone -q "$g/origin.git" "$g/w" 2>/dev/null
c() { git -C "$g/w" -c user.name=t -c user.email=t@t "$@"; }
printf '# C\n<!-- mission -->\nNever lower a baseline.\n<!-- /mission -->\nsteps\n' > "$g/w/C.md"
printf 'plain\n' > "$g/w/N.md"; printf '<!-- mission -->\nopen\n' > "$g/w/U.md"
c add . && c commit -qm c && c push -q origin HEAD:master
expect "mission-guard refuses a file with no blocks" "! bin/mission-guard bless $g/w/N.md 2>/dev/null"
expect "mission-guard refuses an unclosed block" "! bin/mission-guard bless $g/w/U.md 2>/dev/null"
expect "a failed bless records nothing" "[ ! -e $AGENT_OPS_DIR/missions.json ]"
bin/mission-guard bless "$g/w/C.md" >/dev/null
expect "mission-guard check is clean after bless" "bin/mission-guard check | grep -q '^1 of 1 charters clean'"
sed -i.bak 's/Never lower/Always lower/' "$g/w/C.md" && rm "$g/w/C.md.bak"
expect "mission-guard won't bless an unpushed edit" "! bin/mission-guard bless $g/w/C.md 2>/dev/null"
expect "mission-guard check ignores an unpushed edit" "bin/mission-guard check >/dev/null"
expect "mission-guard pr flags the edit in a checkout" "! (cd $g/w && $PWD/bin/mission-guard pr >/dev/null)"
expect "mission-guard pr needs no store" "o=\$(cd $g/w && AGENT_OPS_DIR=\$(mktemp -d) $PWD/bin/mission-guard pr); grep -q '^C.md: ' <<<\"\$o\""
expect "mission-guard pr passes a steps-only change" "(d=\$(mktemp -d) && git clone -q $g/origin.git \$d/c && echo more >> \$d/c/C.md && cd \$d/c && $PWD/bin/mission-guard pr >/dev/null)"
expect "mission-guard pr flags a change to the guard itself" "(d=\$(mktemp -d) && git clone -q $g/origin.git \$d/c && mkdir -p \$d/c/scripts && echo 'print(0)' > \$d/c/scripts/mission-guard && cd \$d/c && $PWD/bin/mission-guard pr >/dev/null; [ \$? = 1 ])"
expect "mission-guard pr flags a CI workflow change" "(d=\$(mktemp -d) && git clone -q $g/origin.git \$d/c && mkdir -p \$d/c/.github/workflows && echo x > \$d/c/.github/workflows/ci.yml && cd \$d/c && $PWD/bin/mission-guard pr >/dev/null; [ \$? = 1 ])"
expect "mission-guard pr fails closed with no origin" "(d=\$(mktemp -d) && git init -q \$d && cd \$d && $PWD/bin/mission-guard pr >/dev/null; [ \$? = 2 ])"
c commit -qam edit && c push -q origin HEAD:master
expect "mission-guard check fails on a pushed edit, with the diff" "o=\$(bin/mission-guard check); [ \$? = 1 ] && grep -q '^    +Always lower' <<<\"\$o\""
out=$(bin/heartbeat.py | tail -1)
expect "heartbeat alerts on mission drift, keyed by the charter" "jq -e '.alerts | any(startswith(\"mission:\") and endswith(\"/w/C.md\"))' <<<'$out' >/dev/null"
cp $AGENT_OPS_DIR/missions.json $AGENT_OPS_DIR/m.bak; echo '{' > $AGENT_OPS_DIR/missions.json
expect "a broken missions.json is a guard failure, not drift" "bin/heartbeat.py | tail -1 | jq -e '.alerts | index(\"mission-guard\")' >/dev/null"
mv $AGENT_OPS_DIR/m.bak $AGENT_OPS_DIR/missions.json
bin/mission-guard bless "$g/w/C.md" >/dev/null
expect "a bless after the push clears it" "bin/mission-guard check >/dev/null"
o=$(mktemp -d); git clone -q "$g/origin.git" "$o/c" 2>/dev/null; mkdir -p "$o/c/docs/orders"
printf '# Orders\n| Order | Moves | Stop rule | Read date |\n|---|---|---|---|\n\n## Changes\n\ndate | why | by\n2026-11-22 | created | you\n' > "$o/c/docs/orders/x.md"
git -C "$o/c" add . && git -C "$o/c" -c user.name=t -c user.email=t@t commit -qm o && git -C "$o/c" push -q origin HEAD:master
python3 - "$o/c/docs/orders/x.md" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,'w').write(s.replace("|---|---|---|---|\n","|---|---|---|---|\n| Ship a page | visits | none | 2026-12-01 |\n")+"2026-11-23 | new order | sup |\n")
PY
expect "mission-guard orders passes one order with one Changes line" "(cd $o/c && $PWD/bin/mission-guard orders >/dev/null)"
echo "2026-11-23 | another | sup |" >> "$o/c/docs/orders/x.md"
expect "mission-guard orders refuses two Changes lines" "! (cd $o/c && $PWD/bin/mission-guard orders >/dev/null)"
git -C "$o/c" checkout -q -- . ; echo x > "$o/c/README.md"
expect "mission-guard orders refuses a non-Orders file" "! (cd $o/c && $PWD/bin/mission-guard orders >/dev/null)"
git -C "$o/c" checkout -q -- . ; git -C "$o/c" clean -qf; cp examples/orders.md "$o/c/docs/orders/new.md"
expect "mission-guard orders passes a new Orders file from the example" "(cd $o/c && $PWD/bin/mission-guard orders >/dev/null)"
rm "$o/c/docs/orders/new.md"; mkdir -p "$o/c/.github/workflows"; echo on: push > "$o/c/.github/workflows/ci.yml"
git -C "$o/c" add . && git -C "$o/c" -c user.name=t -c user.email=t@t commit -qm ci && git -C "$o/c" push -q origin HEAD:master
git -C "$o/c" mv .github/workflows/ci.yml .github/ci.yml
expect "mission-guard pr flags a protected file renamed out" "! (cd $o/c && $PWD/bin/mission-guard pr >/dev/null)"
rm -rf "$o"
rm -rf "$g"

exit $fail
