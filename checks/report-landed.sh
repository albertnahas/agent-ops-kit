#!/bin/bash
# Outcome check for the charter's daily run: today's report has landed, on main or on the
# report-only PR's branch, with every section docs/AGENT_LOOP.md requires. No LLM, free.
# Usage: bin/ops-check -- checks/report-landed.sh [YYYY-MM-DD]
day="${1:-$(date +%F)}"
git fetch -q --prune origin || exit 1
for ref in $(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin); do
  report=$(git show "$ref:docs/ops-reports/$day.md" 2>/dev/null) && break
done
[ -n "$report" ] || { echo "no report for $day on any branch of origin"; exit 1; }
missing=$(for s in TLDR KPIs Findings "Actions taken" Escalations Handoff; do
  grep -qiE "^(#+|[0-9]+\.) *(\*\*)?([0-9]+\. *)?$s" <<<"$report" || printf '%s, ' "$s"; done)
[ -z "$missing" ] || { echo "report $day on $ref lacks: ${missing%, }"; exit 1; }
echo "report $day on $ref, $(wc -l <<<"$report" | tr -d ' ') lines"
