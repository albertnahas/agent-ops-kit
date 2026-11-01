#!/usr/bin/env bash
# The loop's track record as JSON, so people can check you instead of trusting you:
# merged PRs per month, how many the scheduled loop opened, PRs closed unmerged,
# X escalations (label founder), reverts on main, and commits written with Claude Code.
# Usage: SINCE=2026-07-01 LOOP_BRANCH=ops/ scripts/loop-stats.sh   Run inside a clone; needs gh and jq.
set -euo pipefail
SINCE="${SINCE:-1970-01-01}"
LOOP_BRANCH="${LOOP_BRANCH:-ops/}"

prs=$(gh pr list --state all --limit 1000 --json state,mergedAt,createdAt,headRefName,labels \
  | jq --arg s "$SINCE" '[.[] | select(.createdAt >= $s)]')
git fetch -q origin main
commits=$(git log origin/main --first-parent --since="$SINCE" --format='%H' | wc -l | tr -d ' ')
claude=$(git log origin/main --first-parent --since="$SINCE" --format='%B%x00' \
  | tr '\0' '\n' | grep -ci 'co-authored-by: claude' || true)
reverts=$(git log origin/main --first-parent --since="$SINCE" --oneline | grep -ci '^[0-9a-f]* revert' || true)

jq -n --argjson prs "$prs" --arg since "$SINCE" --arg loop "$LOOP_BRANCH" \
  --argjson commits "$commits" --argjson claude "$claude" --argjson reverts "$reverts" '
  [$prs[] | select(.mergedAt != null)] as $m | {
  asOf: (now | strftime("%Y-%m-%d")),
  since: $since,
  merged: ($m | length),
  mergedByLoop: ([$m[] | select(.headRefName | startswith($loop))] | length),
  mergedByMonth: ([$m[] | .mergedAt[0:7]] | group_by(.) | map({month: .[0], merged: length})),
  closedUnmerged: ([$prs[] | select(.state == "CLOSED")] | length),
  escalated: ([$prs[] | select(any(.labels[]; .name == "founder"))] | length),
  openEscalations: ([$prs[] | select(.state == "OPEN" and any(.labels[]; .name == "founder"))] | length),
  reverts: $reverts,
  commits: $commits,
  commitsWithClaude: $claude
}'
