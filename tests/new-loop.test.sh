#!/usr/bin/env bash
# Scaffolds loops with bin/new-loop in a sandbox and holds the result to the kit's own tools: the charter
# blesses and stays clean under mission-guard, a Floor edit is caught, each loop's check fails before its
# report lands and passes after, the runner logs under its loop name, and the registry passes the
# factory's fleet.py --check when the factory is around. A template change new-loop can't fill fails here.
# Usage: tests/new-loop.test.sh   Needs bash, git, jq and python3. HOME and AGENT_OPS_DIR are temp folders;
# launchctl and crontab are stubs that fail the test if anything calls them.
set -uo pipefail
cd "$(dirname "$0")/.."
kit=$PWD factory=${AGENT_OPS_FACTORY:-$HOME/.agent-ops/factory}
s=$(mktemp -d) && trap 'rm -rf "$s"' EXIT
export HOME=$s/home AGENT_OPS_DIR=$s/ops GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$s/stub"
for t in launchctl crontab; do printf '#!/bin/sh\necho "%s $*" >> %s/scheduled; exit 1\n' "$t" "$s" > "$s/stub/$t"; done
printf '#!/bin/sh\necho %s\n' "'{\"result\":\"done\",\"subtype\":\"success\",\"num_turns\":3,\"total_cost_usd\":0.42,\"usage\":{\"input_tokens\":1,\"cache_read_input_tokens\":0,\"cache_creation_input_tokens\":0,\"output_tokens\":1}}'" > "$s/stub/claude"
chmod +x "$s/stub/"*; export PATH="$s/stub:$PATH"
fail=0
expect() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
tty() { python3 -c 'import os, subprocess, sys; m, s = os.openpty(); os.write(m, (sys.argv[1] + "\n").encode()); sys.exit(subprocess.call(sys.argv[2:], stdin=s))' "$@"; }

git init -q --bare "$s/origin.git" && git -C "$s/origin.git" symbolic-ref HEAD refs/heads/trunk
git clone -q "$s/origin.git" "$s/app" 2>/dev/null && cd "$s/app" && git checkout -q -b trunk
git commit -q --allow-empty -m init && git push -q origin HEAD
land() { git add -A && git commit -qm "$1" && git push -q origin HEAD; }
scaffold() { "$kit/bin/new-loop" --repo "$s/app" --mission "Keep issues triaged and p95 < 200ms; never close one a person opened without a reply (> 0)." \
  --limits "At most 20 comments a day." --outcome "Every new issue gets a label within a day." --source "origin's commit history" \
  --schedule "0 2 * * *" --x-surface "the billing folder" "$@"; }

out=$(scaffold --name triage --runtime launchd --floor "at least 1 commit" --measure "git rev-list --count origin/trunk" --project App 2>&1)
expect "new-loop scaffolds a launchd loop from the kit's template" "[ \$? = 0 ] || { echo \"\$out\"; false; }"
c=docs/loops/triage.md
expect "the charter carries the user's words in its mission blocks" "grep -qF 'Keep issues triaged and p95 < 200ms; never close one a person opened without a reply (> 0).' $c && grep -q '^At most 20 comments a day.' $c && grep -q '^- the billing folder' $c"
expect "the Good block is filled and the Floor is the user's" "grep -q '^## Good' $c && grep -q '^- \*\*Floor:\*\* at least 1 commit$' $c && grep -q 'checks/triage.py' $c"
expect "the kill switch names the launchd job" "grep -q 'launchctl bootout gui/\$(id -u)/com.agent-ops.triage' $c"
expect "reports go to the loop's own folder" "grep -q 'docs/ops-reports/triage/' $c && ! grep -q 'docs/ops-reports/YYYY' $c"
expect "the Orders file names the loop, keeps no example Orders and logs one line" "grep -q '^# Orders: triage' docs/orders/triage.md && ! grep -q wedding docs/orders/triage.md && [ \$(grep -c '| new-loop |\| from new-loop |' docs/orders/triage.md) = 1 ]"
expect "the charter links its Orders, whose Target starts at the Floor" "grep -q 'docs/orders/triage.md' $c && grep -q '^Target: at least 1 commit ' docs/orders/triage.md"
expect "the runner exports OPS_LOOP with cost caps" "grep -q '^export OPS_LOOP=triage' $AGENT_OPS_DIR/runners/triage.sh && grep -q 'max-budget-usd 5' $AGENT_OPS_DIR/runners/triage.sh && grep -q 'max-turns 60' $AGENT_OPS_DIR/runners/triage.sh"
expect "the plist runs the runner at 02:00 and isn't installed" "python3 -c 'import plistlib,sys; p=plistlib.load(open(sys.argv[1],\"rb\")); assert p[\"StartCalendarInterval\"]=={\"Hour\":2,\"Minute\":0} and p[\"ProgramArguments\"]==[sys.argv[2]]' $AGENT_OPS_DIR/schedules/com.agent-ops.triage.plist $AGENT_OPS_DIR/runners/triage.sh && [ ! -e $HOME/Library/LaunchAgents ]"
expect "the registry gets one row with its check and reader" "grep -q '^| triage | App | mac | com.agent-ops.triage | 0 2 \* \* \* | \`docs/loops/triage.md\` | .*checks/triage.py.* | you |' $AGENT_OPS_DIR/REGISTRY.md"
expect "the repo gets the grader, the hooks and the guard it relies on" "[ -x scripts/mission-guard ] && [ -x bin/claude-run ] && [ -f .claude/agents/pr-grader.md ] && [ -f .claude/settings.json ]"
expect "a repo's own settings are kept, with a note to wire the guard" "d=\$(mktemp -d) && git init -q \$d && mkdir \$d/.claude && echo '{}' > \$d/.claude/settings.json && \"\$kit/bin/new-loop\" --repo \$d --name other --mission m --limits l --outcome o --source s --schedule '0 2 * * *' --runtime cron --floor 'unmeasured: x' | grep -q 'merge the kit.s PreToolUse guard hook' && [ \"\$(cat \$d/.claude/settings.json)\" = '{}' ]"
expect "new-loop won't overwrite a loop" "! scaffold --name triage --runtime launchd --floor 'unmeasured: x' >/dev/null 2>&1"

land "triage loop"
guarded=$(grep -lx '[[:space:]]*<!-- mission -->[[:space:]]*' docs/loops/*.md docs/orders/*.md)
tty "$(for f in $guarded; do printf '%s ' "${f##*/}"; done | sed 's/ $//')" "$kit/bin/mission-guard" bless $guarded >/dev/null
expect "mission-guard blesses the charter and finds it clean" "out=\$($kit/bin/mission-guard check); [ \$? = 0 ] && grep -q \"^\$(wc -w <<<\"\$guarded\" | tr -d ' ') of \" <<<\"\$out\""
git checkout -q -b lower && sed -i.bak 's/at least 1 commit$/at least 0 commits/' $c && rm $c.bak && git commit -qam lower
expect "mission-guard pr makes a Floor edit X" "! $kit/bin/mission-guard pr >/dev/null"
git checkout -q trunk && git checkout -q -b orders && echo "$(date +%F) | first review | you" >> docs/orders/triage.md && git commit -qam orders
expect "mission-guard orders passes the scaffolded Orders with one appended line" "$kit/bin/mission-guard orders >/dev/null"
git checkout -q trunk

check="$kit/bin/ops-check -- python3 $AGENT_OPS_DIR/checks/triage.py"
expect "the check fails before today's report lands" "! OPS_LOOP=triage $check >/dev/null"
report() { mkdir -p "docs/ops-reports/$1" && printf '## TLDR\n- x\n## KPIs\nx\n## Findings\nx\n## Actions taken\nx\n## Escalations\nx\n## Handoff\nx\n' > "docs/ops-reports/$1/$(date +%F).md"; }
report triage
git checkout -q -b "ops/triage-$(date +%F)-report" && land report && git checkout -q trunk
expect "ops-check passes the loop's own check once its report is on a branch" "OPS_LOOP=triage $check | grep -q '\"loop\":\"triage\",.*\"check\":\"pass\"'"
"$AGENT_OPS_DIR/runners/triage.sh"
expect "the runner logs Claude's run and the check under the loop's name" "grep -q '\"loop\":\"triage\".*\"subtype\":\"success\".*\"cost\":0.42' $AGENT_OPS_DIR/runs.jsonl && tail -1 $AGENT_OPS_DIR/runs.jsonl | grep -q '\"loop\":\"triage\",.*\"check\":\"pass\"'"

out=$(scaffold --name growth --runtime cron --schedule "30 6 * * 1-5" --floor "at least 1000 commits" --measure "git rev-list --count origin/trunk" --checked-by triage --budget 2.5 --turns 20 --outcome "merged PRs | week" --project "A|B" 2>&1)
expect "new-loop scaffolds a cron loop next to the first" "[ \$? = 0 ] && grep -q '^30 6 \* \* 1-5 PATH=.* AGENT_OPS_DIR=.*runners/growth.sh' $AGENT_OPS_DIR/schedules/growth.cron"
expect "a | in an answer is escaped in the KPI table and the registry" "grep -qF '| merged PRs \\| week | at least 1000 commits |' docs/loops/growth.md && grep -qF '| growth | A\\|B | cron |' $AGENT_OPS_DIR/REGISTRY.md"
report growth && land growth
expect "a check fails when the Floor's number isn't met" "! python3 $AGENT_OPS_DIR/checks/growth.py > $s/growth.out && grep -q 'is not at least the Floor of 1000' $s/growth.out"
out=$(scaffold --name weekly --runtime cloud --schedule "0 9 * * 1" --floor "unmeasured: no issue data yet" --supervisor triage 2>&1)
expect "new-loop writes a cloud routine prompt that points at the charter" "[ \$? = 0 ] && grep -q 'Read docs/loops/weekly.md and run it' $AGENT_OPS_DIR/schedules/weekly.routine.md && [ ! -e $AGENT_OPS_DIR/runners/weekly.sh ]"
expect "a supervised loop is checked by its supervisor" "grep -q '^| weekly |  | cloud | routine:weekly | .* | triage | triage |  |  |\$' $AGENT_OPS_DIR/REGISTRY.md && grep -q '^Supervisor: triage, Mondays' docs/orders/weekly.md"
expect "launchd refuses a schedule it can't express" "! scaffold --name ranged --runtime launchd --schedule '0 9 * * 1-5' --floor 'unmeasured: x' >/dev/null 2>&1"
expect "the registry holds all three loops" "[ \$(grep -cE '^\| (triage|growth|weekly) \|' $AGENT_OPS_DIR/REGISTRY.md) = 3 ]"
out=$(scaffold --name desk --runtime app --floor "unmeasured: x" 2>&1)
expect "new-loop writes a desktop app task the registry and kill switch name" "[ \$? = 0 ] && [ -f $AGENT_OPS_DIR/schedules/desk.task.md ] && grep -q '^| desk |  | app | task:desk |' $AGENT_OPS_DIR/REGISTRY.md && grep -q 'disable the scheduled task \`desk\`' docs/loops/desk.md"
touch $AGENT_OPS_DIR/schedules/app-triage.cron $AGENT_OPS_DIR/schedules/nope.cron
out=$("$kit/bin/new-loop" --reschedule --repo "$s/app" --name triage --runtime cron --schedule "15 3 * * *" 2>&1)
expect "--reschedule moves a loop from launchd to cron" "[ \$? = 0 ] && grep -q '^| triage | App | cron | cron:triage.sh | 15 3 \* \* \* |' $AGENT_OPS_DIR/REGISTRY.md && grep -q '^15 3 ' $AGENT_OPS_DIR/schedules/triage.cron && [ ! -e $AGENT_OPS_DIR/schedules/com.agent-ops.triage.plist ] && [ -x $AGENT_OPS_DIR/runners/triage.sh ]"
expect "--reschedule rewrites the kill switch and says it's a founder PR" "grep -q \"Hard stop:\*\* \\\`crontab -l | grep -v 'runners/triage.sh'\" $c && grep -q 'founder PR' <<<\"\$out\" && grep -q 'Stop the old schedule: launchctl bootout gui/\$(id -u)/com.agent-ops.triage; rm ~/Library/LaunchAgents/com.agent-ops.triage.plist' <<<\"\$out\""
expect "--reschedule refuses a loop it doesn't know, before touching its files" "! $kit/bin/new-loop --reschedule --repo $s/app --name nope --runtime cron --schedule '0 1 * * *' >/dev/null 2>&1 && [ -e $AGENT_OPS_DIR/schedules/nope.cron ]"
expect "--reschedule leaves other loops' files alone" "[ -e $AGENT_OPS_DIR/schedules/app-triage.cron ]"
"$kit/bin/new-loop" --reschedule --repo "$s/app" --name growth --runtime launchd --schedule "0 7 * * *" >/dev/null
expect "--reschedule keeps the runner's own caps, decimals included" "grep -q 'max-budget-usd 2.5' $AGENT_OPS_DIR/runners/growth.sh && grep -q 'max-turns 20' $AGENT_OPS_DIR/runners/growth.sh && [ ! -e $AGENT_OPS_DIR/schedules/growth.cron ]"
expect "every question in the spec is a new-loop flag" "h=\$($kit/bin/new-loop --help); ! jq -r '.new[].id' $kit/skills/new-loop/questions.json | while read q; do grep -q -- \"--\$q \" <<<\"\$h\" || echo \$q; done | grep -q ."
expect "nothing was installed with launchctl or crontab" "[ ! -e $s/scheduled ]"

if [ -f "$factory/fleet/fleet.py" ]; then
  expect "the registry passes the factory's fleet.py --check" "python3 $factory/fleet/fleet.py --check"
else
  echo "skip  fleet.py --check: no factory at $factory (set AGENT_OPS_FACTORY)"
fi
exit $fail
