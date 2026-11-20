#!/bin/bash
# Outcome check for the charter's daily run: today's report is on origin/main (it lands
# through a PR) and has every section docs/AGENT_LOOP.md requires. No LLM, costs nothing.
# Usage: bin/ops-check -- checks/report-landed.sh [YYYY-MM-DD]
day="${1:-$(date +%F)}"
git fetch -q origin main || exit 1
report=$(git show "origin/main:docs/ops-reports/$day.md" 2>/dev/null) || { echo "no report for $day on main"; exit 1; }
missing=$(for s in TLDR KPIs Findings "Actions taken" Escalations Handoff; do
  grep -qiE "^#+ *(\*\*)?[0-9. ]*$s" <<<"$report" || printf '%s, ' "$s"; done)
[ -z "$missing" ] || { echo "report $day lacks: ${missing%, }"; exit 1; }
echo "report $day on main, $(wc -l <<<"$report" | tr -d ' ') lines"
