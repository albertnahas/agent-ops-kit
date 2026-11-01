#!/usr/bin/env bash
# What the loop did since a given time (default: 24 hours ago). Read it with your coffee.
# Usage: scripts/night-summary.sh [ISO date]   Needs gh, authenticated for this repo.
set -euo pipefail
SINCE="${1:-$(date -u -v-24H +%FT%TZ 2>/dev/null || date -u -d '24 hours ago' +%FT%TZ)}"

echo "Since $SINCE"
echo
echo "Merged:"
gh pr list --state merged --limit 200 --json number,title,mergedAt \
  --jq ".[] | select(.mergedAt >= \"$SINCE\") | \"  #\(.number) \(.title)\""
echo
echo "Closed without merging:"
gh pr list --state closed --limit 200 --json number,title,closedAt,mergedAt \
  --jq ".[] | select(.mergedAt == null and .closedAt >= \"$SINCE\") | \"  #\(.number) \(.title)\""
echo
echo "Waiting for you (label founder):"
gh pr list --state open --label founder --json number,title,createdAt \
  --jq '.[] | "  #\(.number) \(.title) (open since \(.createdAt[0:10]))"'
echo
echo "Reverts on main:"
git fetch -q origin main
git log origin/main --since="$SINCE" --oneline | grep -i 'revert' | sed 's/^/  /' || echo "  none"
