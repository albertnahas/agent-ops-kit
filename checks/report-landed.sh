#!/bin/bash
# Outcome check for the charter's daily run: today's report has landed, on the default branch or on
# its report PR's branch, ops/YYYY-MM-DD-report, with every section docs/AGENT_LOOP.md requires and
# something written under each. No LLM, free. Usage: bin/ops-check -- checks/report-landed.sh [YYYY-MM-DD]
day="${1:-$(date +%F)}"
git fetch -q --prune origin || exit 1
main=$(git ls-remote --symref origin HEAD | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p')
for ref in "origin/$main" "origin/ops/$day-report"; do
  report=$(git show "$ref:docs/ops-reports/$day.md" 2>/dev/null) && break
done
[ -n "$report" ] || { echo "no report for $day on origin/$main or origin/ops/$day-report"; exit 1; }
sections="TLDR KPIs Findings Actions_taken Escalations Handoff"
missing=$(awk -v want="$sections" '
  function head(line,  i) {  # the section a heading line opens, and what follows its name on that line
    line = tolower(line); if (line !~ /^(#+|[0-9]+\.) /) return 0
    sub(/^(#+|[0-9]+\.) *(\*\*)?([0-9]+\. *)?/, "", line)
    for (i = 1; i <= n; i++) if (index(line, w[i]) == 1) { rest = substr(line, length(w[i]) + 1); return i }
    return 0 }
  BEGIN { n = split(tolower(want), w, " "); for (i = 1; i <= n; i++) gsub("_", " ", w[i]) }
  (h = head($0)) { cur = h; seen[h] = 1; if (rest ~ /[[:alnum:]]/) body[h] = 1; next }
  /^#+ / { cur = 0; next }
  cur && /[[:alnum:]]/ { body[cur] = 1 }
  END { for (i = 1; i <= n; i++) if (!body[i]) printf "%s%s, ", w[i], seen[i] ? " (empty)" : "" }' <<<"$report")
[ -z "$missing" ] || { echo "report $day on $ref lacks: ${missing%, }"; exit 1; }
echo "report $day on $ref, $(wc -l <<<"$report" | tr -d ' ') lines"
