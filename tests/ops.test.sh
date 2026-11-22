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

day() { date -v-"$1"d +%FT%T 2>/dev/null || date -d "$1 days ago" +%FT%T; }  # now, days back: never in the future
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
expect "heartbeat writes COSTS.md" "grep -q '| pricey | 7 | 0 | 0 | \\\$15.00' $AGENT_OPS_DIR/COSTS.md"
expect "heartbeat logs its own pass line" "tail -1 $AGENT_OPS_DIR/runs.jsonl | grep -q '\"loop\": \"heartbeat\"'"
expect "an alert is sent once, then held for 3 days" "[ \"\$(bin/heartbeat.py | tail -1 | jq -c .sent)\" = '[]' ]"
h=$(mktemp -d); echo "{\"loop\":\"x\",\"date\":\"$(day 1)\",\"check\":\"fail\"}" > "$h/runs.jsonl"; AGENT_OPS_DIR=$h bin/heartbeat.py >/dev/null
echo "{\"loop\":\"x\",\"date\":\"$(day 0)\",\"check\":\"fail\"}" >> "$h/runs.jsonl"
expect "a check failing again the next day is held too" "[ \"\$(AGENT_OPS_DIR=$h bin/heartbeat.py | tail -1 | jq -c .sent)\" = '[]' ]"; rm -rf "$h"
expect "ops-check with no command is a usage error, not a pass" "! bin/ops-check -l empty -- 2>/dev/null && ! grep -q '\"loop\":\"empty\"' $AGENT_OPS_DIR/runs.jsonl"

# the watchman survives any ledger: bad bytes, a cut last line, odd field types, Z and offset dates, a future date
j=$(mktemp -d)
{ echo "{\"loop\":\"z\",\"date\":\"$(day 2)Z\",\"check\":\"pass\"}"; echo "{\"loop\":\"z\",\"date\":\"$(day 1).5-0100\",\"check\":\"pass\"}"; echo "{\"loop\":\"z\",\"date\":\"$(day 0)+05:30\",\"check\":\"pass\"}"
  echo '{"loop":["l"],"date":"2026-11-01T10:00:00"}'; echo '{"loop":"c","date":"","cost":"9"}'; echo '{"loop":"c","date":"2999-01-01T00:00:00"}'
  echo "{\"loop\":\"c\",\"date\":\"$(day 1)\",\"subtype\":\"success\",\"cost\":\"lots\"}"; printf 'nul\0 and \303(\n'; printf '{"loop":"cut","date":"2026-11-0'; } > "$j/runs.jsonl"
expect "heartbeat skips junk lines with an alert and logs its own line apart" "AGENT_OPS_DIR=$j bin/heartbeat.py | tail -1 | jq -e '[.alerts[] | select(startswith(\"ledger:\"))] | length == 5' >/dev/null && tail -1 $j/runs.jsonl | jq -e '.loop == \"heartbeat\"' >/dev/null"
rm -rf "$j"
# hooks in heartbeat.d filter the alerts and name files to commit; a broken one is an alert, never a crash; the notifier gets the due alerts by key
k=$(mktemp -d); mkdir "$k/heartbeat.d"
{ echo "{\"loop\":\"crashed-ok\",\"date\":\"$(day 0)\",\"subtype\":\"success\",\"exit\":1}"; echo "{\"loop\":\"x\",\"date\":\"$(day 0)\",\"check\":\"fail\"}"; } > "$k/runs.jsonl"
printf '#!/usr/bin/env python3\nimport json, sys\nc = json.load(sys.stdin)\na = {k: v for k, v in c["alerts"].items() if not k.startswith("check:")}\na["seen"] = str(len(c["runs"]))\nprint(json.dumps({"alerts": a, "commit": ["EXTRA.md"]}))\n' > "$k/heartbeat.d/10-filter"
printf '#!/bin/sh\necho not json\n' > "$k/heartbeat.d/20-broken"; printf '#!/bin/sh\nexit 3\n' > "$k/heartbeat.d/30-ignored"
chmod +x "$k/heartbeat.d/10-filter" "$k/heartbeat.d/20-broken"
o=$(AGENT_OPS_DIR=$k AGENT_OPS_NOTIFY="sh -c 'cat > $k/due.json' n" bin/heartbeat.py | tail -1)
expect "heartbeat counts a run that says success but exited non-zero as crashed" "jq -e '.alerts | index(\"run:crashed-ok\")' <<<'$o' >/dev/null"
expect "a heartbeat hook drops and adds alerts" "jq -e '.alerts | (index(\"check:x\") | not) and index(\"seen\")' <<<'$o' >/dev/null"
expect "a broken hook is an alert and leaves the alerts as they were" "jq -e '.alerts | index(\"hook:20-broken\") and index(\"seen\")' <<<'$o' >/dev/null"
expect "a hook that isn't executable doesn't run" "! jq -e '.alerts | index(\"hook:30-ignored\")' <<<'$o' >/dev/null"
expect "the notifier gets the due alerts by key on stdin" "jq -e 'has(\"seen\") and has(\"run:crashed-ok\")' $k/due.json >/dev/null"
rm -rf "$k"
for n in false /no/such/notifier "'unclosed"; do j=$(mktemp -d); echo "{\"loop\":\"x\",\"date\":\"$(day 0)\",\"check\":\"fail\"}" > "$j/runs.jsonl"
  expect "a notifier that fails ($n) makes the heartbeat's own line a fail" "AGENT_OPS_DIR=$j AGENT_OPS_NOTIFY=\"$n\" bin/heartbeat.py >/dev/null 2>&1; tail -1 $j/runs.jsonl | jq -e '.check == \"fail\" and (.detail | contains(\"notifier\"))' >/dev/null"; rm -rf "$j"; done

# git: it syncs only its own repo, and two writers to runs.jsonl never wedge it
r=$(mktemp -d); git init -q --bare "$r/o.git"; git clone -q "$r/o.git" "$r/a" 2>/dev/null; git clone -q "$r/o.git" "$r/b" 2>/dev/null
g2() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
echo '{"loop":"b","date":"2026-11-01T10:00:00","check":"pass"}' > "$r/b/runs.jsonl"; g2 "$r/b" add -A; g2 "$r/b" commit -qm b; g2 "$r/b" push -q origin HEAD
echo '{"loop":"a","date":"2026-11-01T11:00:00","check":"pass"}' > "$r/a/runs.jsonl"
AGENT_OPS_DIR="$r/a" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t bin/heartbeat.py >/dev/null
expect "two writers' ledger lines merge and push" "g2 $r/a fetch -q && [ \$(g2 $r/a show origin/HEAD:runs.jsonl | grep -c '\"loop\"') = 3 ] && ! grep -q '<<<<' $r/a/runs.jsonl"
echo '{}' > "$r/a/missions.json"; g2 "$r/a" add missions.json; g2 "$r/a" commit -qm m; g2 "$r/a" push -q origin HEAD; echo '{"x":1}' > "$r/a/missions.json"; mkdir "$r/a/fleet"; echo page > "$r/a/fleet/dashboard.html"
g2 "$r/b" pull -q; echo remote > "$r/b/note.md"; g2 "$r/b" add note.md; g2 "$r/b" commit -qm b2; g2 "$r/b" push -q origin HEAD
expect "heartbeat commits only the ledger and COSTS.md, and syncs past other local edits" "AGENT_OPS_DIR=$r/a GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t bin/heartbeat.py >/dev/null && g2 $r/a fetch -q && [ \"\$(g2 $r/a diff --name-only HEAD~1 HEAD | sort | tr '\\n' ' ')\" = 'COSTS.md runs.jsonl ' ] && [ \"\$(g2 $r/a status --porcelain)\" = \"\$(printf ' M missions.json\\n?? alerts.json\\n?? fleet/')\" ] && [ \$(g2 $r/a rev-parse HEAD) = \$(g2 $r/a rev-parse origin/HEAD) ]"
g2 "$r/b" pull -q; echo '{"b":1}' > "$r/b/missions.json"; g2 "$r/b" commit -qam b3; g2 "$r/b" push -q origin HEAD
expect "local edits that clash with the remote fail the sync and stay as they were" "AGENT_OPS_DIR=$r/a GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t bin/heartbeat.py >/dev/null; tail -1 $r/a/runs.jsonl | grep -q 'clash with the remote' && [ \"\$(cat $r/a/missions.json)\" = '{\"x\":1}' ] && [ -z \"\$(g2 $r/a ls-files -u)\$(g2 $r/a stash list)\" ]"
mkdir -p "$r/a/inner/.git"; echo '{"loop":"i","date":"2026-11-01T11:00:00","check":"pass"}' > "$r/a/inner/runs.jsonl"; head=$(g2 "$r/a" rev-parse HEAD)
expect "an empty .git inside never commits the enclosing repo" "AGENT_OPS_DIR=$r/a/inner bin/heartbeat.py >/dev/null && [ \$(g2 $r/a rev-parse HEAD) = $head ]"
mkdir "$r/c" && git init -q --bare "$r/c/o.git" && git clone -q "$r/c/o.git" "$r/c/w" 2>/dev/null && mkdir "$r/c/w/heartbeat.d"
printf '#!/bin/sh\necho made > "$AGENT_OPS_DIR/EXTRA.md"; echo "{\\"alerts\\": {}, \\"commit\\": [\\"EXTRA.md\\"]}"\n' > "$r/c/w/heartbeat.d/board"; chmod +x "$r/c/w/heartbeat.d/board"
expect "the sync commits the files a hook names" "AGENT_OPS_DIR=$r/c/w GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t bin/heartbeat.py >/dev/null && [ \"\$(g2 $r/c/w show --name-only --format= HEAD | sort | tr '\\n' ' ')\" = 'COSTS.md EXTRA.md runs.jsonl ' ]"
rm -rf "$r"

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
