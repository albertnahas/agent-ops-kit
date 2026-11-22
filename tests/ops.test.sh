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
echo "{\"loop\":\"broken\",\"date\":\"$(day 0)\",\"check\":\"fail\",\"detail\":\"again\"}" >> "$AGENT_OPS_DIR/runs.jsonl"
expect "a check failing again the next day is held too" "[ \"\$(bin/heartbeat.py | tail -1 | jq -c .sent)\" = '[]' ]"
expect "ops-check with no command is a usage error, not a pass" "! bin/ops-check -l empty -- 2>/dev/null && ! grep -q '\"loop\":\"empty\"' $AGENT_OPS_DIR/runs.jsonl"

# the watchman survives any ledger: bad bytes, a cut last line, odd field types, Z and offset dates, a future date
j=$(mktemp -d)
{ echo "{\"loop\":\"z\",\"date\":\"$(day 1)Z\",\"check\":\"pass\"}"; echo "{\"loop\":\"z\",\"date\":\"$(day 0)+05:30\",\"check\":\"pass\"}"
  echo '{"loop":["l"],"date":"2026-11-01T10:00:00"}'; echo '{"loop":"c","date":"","cost":"9"}'; echo '{"loop":"c","date":"2999-01-01T00:00:00"}'
  echo "{\"loop\":\"c\",\"date\":\"$(day 1)\",\"subtype\":\"success\",\"cost\":\"lots\"}"; printf 'nul\0 and \303(\n'; printf '{"loop":"cut","date":"2026-11-0'; } > "$j/runs.jsonl"
expect "heartbeat skips junk lines with an alert and logs its own line apart" "AGENT_OPS_DIR=$j bin/heartbeat.py | tail -1 | jq -e '[.alerts[] | select(startswith(\"ledger:\"))] | length == 5' >/dev/null && tail -1 $j/runs.jsonl | jq -e '.loop == \"heartbeat\"' >/dev/null"
rm -rf "$j"
for n in false /no/such/notifier "'unclosed"; do j=$(mktemp -d); echo "{\"loop\":\"x\",\"date\":\"$(day 0)\",\"check\":\"fail\"}" > "$j/runs.jsonl"
  expect "a notifier that fails ($n) makes the heartbeat's own line a fail" "AGENT_OPS_DIR=$j AGENT_OPS_NOTIFY=\"$n\" bin/heartbeat.py >/dev/null 2>&1; tail -1 $j/runs.jsonl | jq -e '.check == \"fail\" and (.detail | contains(\"notifier\"))' >/dev/null"; rm -rf "$j"; done

# git: it syncs only its own repo, and two writers to runs.jsonl never wedge it
r=$(mktemp -d); git init -q --bare "$r/o.git"; git clone -q "$r/o.git" "$r/a" 2>/dev/null; git clone -q "$r/o.git" "$r/b" 2>/dev/null
g2() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
echo '{"loop":"b","date":"2026-11-01T10:00:00","check":"pass"}' > "$r/b/runs.jsonl"; g2 "$r/b" add -A; g2 "$r/b" commit -qm b; g2 "$r/b" push -q origin HEAD
echo '{"loop":"a","date":"2026-11-01T11:00:00","check":"pass"}' > "$r/a/runs.jsonl"
AGENT_OPS_DIR="$r/a" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t bin/heartbeat.py >/dev/null
expect "two writers' ledger lines merge and push" "g2 $r/a fetch -q && [ \$(g2 $r/a show origin/HEAD:runs.jsonl | grep -c '\"loop\"') = 3 ] && ! grep -q '<<<<' $r/a/runs.jsonl"
mkdir -p "$r/a/inner/.git"; echo '{"loop":"i","date":"2026-11-01T11:00:00","check":"pass"}' > "$r/a/inner/runs.jsonl"; head=$(g2 "$r/a" rev-parse HEAD)
expect "an empty .git inside never commits the enclosing repo" "AGENT_OPS_DIR=$r/a/inner bin/heartbeat.py >/dev/null && [ \$(g2 $r/a rev-parse HEAD) = $head ]"
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
expect "mission-guard pr flags a change to the guard itself" "(d=\$(mktemp -d) && git clone -q $g/origin.git \$d/c && mkdir -p \$d/c/scripts && echo 'print(0)' > \$d/c/scripts/mission-guard && cd \$d/c && git add -A && $PWD/bin/mission-guard pr >/dev/null; [ \$? = 1 ])"
expect "mission-guard pr flags a CI workflow change" "(d=\$(mktemp -d) && git clone -q $g/origin.git \$d/c && mkdir -p \$d/c/.github/workflows && echo x > \$d/c/.github/workflows/ci.yml && cd \$d/c && git add -A && $PWD/bin/mission-guard pr >/dev/null; [ \$? = 1 ])"
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
git -C "$o/c" checkout -q -- . ; echo x > "$o/c/README.md"; git -C "$o/c" add -A
expect "mission-guard orders refuses a non-Orders file" "! (cd $o/c && $PWD/bin/mission-guard orders >/dev/null)"
git -C "$o/c" reset -q --hard; git -C "$o/c" clean -qf; cp examples/orders.md "$o/c/docs/orders/new.md"; git -C "$o/c" add -A
expect "mission-guard orders passes a new Orders file from the example" "(cd $o/c && $PWD/bin/mission-guard orders >/dev/null)"
rm "$o/c/docs/orders/new.md"; mkdir -p "$o/c/.github/workflows"; echo on: push > "$o/c/.github/workflows/ci.yml"
git -C "$o/c" add . && git -C "$o/c" -c user.name=t -c user.email=t@t commit -qm ci && git -C "$o/c" push -q origin HEAD:master
git -C "$o/c" mv .github/workflows/ci.yml .github/ci.yml
expect "mission-guard pr flags a protected file renamed out" "! (cd $o/c && $PWD/bin/mission-guard pr >/dev/null)"
rm -rf "$o"
rm -rf "$g"

# mission-guard hardening: quoted paths, agent config, unpaired markers, Orders log lines, empty store, merge-base
h=$(mktemp -d); git init -q --bare -b main "$h/o.git"; git clone -q "$h/o.git" "$h/w" 2>/dev/null; mkdir -p "$h/w/docs/orders"
printf '<!-- mission -->\nNever merge X.\n<!-- /mission -->\n' > "$h/w/docs/C.md";
printf '# Orders\n\nDo the thing.\n\n## Changes\n\ndate | why | by\n2026-11-01 | start | you\n' > "$h/w/docs/orders/a.md"
hc() { git -C "$h/w" -c user.name=t -c user.email=t@t "$@"; }
hc add -A && hc commit -qm base && hc push -q origin HEAD:main
guard() { (cd "$h/w" && "$OLDPWD/bin/mission-guard" "$@" >/dev/null); echo $?; }
reset() { hc checkout -q -f main && hc reset -q --hard origin/main && hc clean -qfd; hc checkout -q -B pr; }
for f in .github/workflows/é.yml .github/actions/x/action.yml pkg/.claude/settings.json CLAUDE.local.md AGENTS.md .claude/settings.local.json .claude/skills/x/SKILL.md .claude/commands/x.md CLAUDE.md docs/CLAUDE.md .mcp.json .husky/pre-commit scripts/run.sh bin/claude-run bin/ops-check checks/report-landed.sh; do
  reset; mkdir -p "$h/w/$(dirname "$f")"; echo x > "$h/w/$f"; hc add -Af; hc commit -qm p
  expect "mission-guard pr protects $f" "[ \$(guard pr) = 1 ]"
done
reset; hc checkout -q main; cp "$h/w/docs/C.md" "$h/w/docs/CHARTÉ.md"; hc add -A; hc commit -qm uni; hc push -q origin HEAD:main
reset; echo hi > "$h/w/README.md"
expect "mission-guard pr passes an unrelated PR next to a non-ASCII charter" "[ \$(guard pr) = 0 ]"
mkdir -p "$h/w/.claude/worktrees/w1"; echo x > "$h/w/.claude/worktrees/w1/f"
expect "mission-guard pr ignores untracked files, a worktree under .claude/ included" "[ \$(GIT_CONFIG_GLOBAL=/dev/null guard pr) = 0 ]"
rm -r "$h/w/.claude"
hc add -A; hc commit -qm r; hc checkout -q main; hc reset -q --hard origin/main
printf '<!-- mission -->\nnever spend money\n' >> "$h/w/docs/C.md"; hc commit -qam unclosed; hc push -q origin HEAD:main
hc checkout -q pr; hc rebase -q main; sed -i.b 's/never spend money/spend freely/; s/Never merge/Always merge/' "$h/w/docs/C.md"; rm "$h/w/docs/C.md.b"
expect "mission-guard pr fails closed on an unclosed block on the default branch" "[ \$(guard pr) = 2 ]"
hc checkout -q -f main; hc revert --no-edit HEAD >/dev/null; hc push -q origin HEAD:main
reset; perl -0pi -e 's/Do the thing./Merge every PR./; s/## Changes/## Changes\n## Changes/' "$h/w/docs/orders/a.md"
expect "mission-guard orders refuses a second Changes heading" "[ \$(guard orders) = 1 ]"
reset; perl -0pi -e 's/Do the thing./Merge every PR./' "$h/w/docs/orders/a.md"; echo x >> "$h/w/docs/orders/a.md"
expect "mission-guard orders refuses an undated Changes line" "[ \$(guard orders) = 1 ]"
reset; perl -0pi -e 's/Do the thing./Do the other thing./' "$h/w/docs/orders/a.md"; echo '2026-11-20 | new thing | sup' >> "$h/w/docs/orders/a.md"; hc commit -qam o
hc checkout -q main; sed -i.b 's/Never merge/Always merge/' "$h/w/docs/C.md"; rm "$h/w/docs/C.md.b"; hc commit -qam main-moved; hc push -q origin HEAD:main; hc checkout -q pr
expect "mission-guard orders judges a stale PR from its merge-base" "[ \$(guard orders) = 0 ]"
expect "mission-guard pr doesn't blame a stale PR for main's mission edit" "[ \$(guard pr) = 0 ]"
s=$(mktemp -d); echo '{}' > "$s/missions.json"
expect "mission-guard check calls an empty store unguarded" "AGENT_OPS_DIR=$s bin/mission-guard check >/dev/null; [ \$? = 2 ]"
rm "$s/missions.json"
expect "mission-guard check calls a missing store unguarded" "AGENT_OPS_DIR=$s bin/mission-guard check >/dev/null; [ \$? = 2 ]"
rm -rf "$h" "$s"

exit $fail
