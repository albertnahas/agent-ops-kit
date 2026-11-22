#!/usr/bin/env bash
# Runs one loop. Point cron, launchd or CI at this file.
# The charter's status line is checked here, before Claude starts, so a pause holds
# even if the model would have misread it. The run is logged by bin/claude-run and
# judged by its outcome check, not by Claude's exit code.
# The session can't forge that check: its Bash runs in Claude Code's sandbox, which
# can't write $AGENT_OPS_DIR (the ledger), and the runner, the logger and the check run
# from the default branch's copies, kept where the session can't write. All of it sits
# in one function, so bash has read this whole file before Claude starts.
set -uo pipefail
main() {
  cd "$(dirname "$0")/.."
  local CHARTER="docs/AGENT_LOOP.md" ops="${AGENT_OPS_DIR:-$HOME/.agent-ops}" branch tools settings f
  mkdir -p logs "$ops"

  if ! grep -q '^status: active' "$CHARTER"; then
    echo "$(date +%FT%T%z) paused by charter, not starting" >> logs/agent.log
    return 0
  fi

  ops=$(cd "$ops" && pwd -P)
  branch=$(git ls-remote --symref origin HEAD | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p')
  tools=$(mktemp -d "$ops/run.XXXXXX") && trap "rm -rf '$tools'" EXIT
  git fetch -q origin "$branch" || return 1
  for f in bin/claude-run bin/ops-check checks/report-landed.sh; do
    git show "origin/$branch:$f" > "$tools/${f##*/}" && chmod +x "$tools/${f##*/}" || return 1
  done
  settings=$(jq -cn --arg ops "$ops" '{
    sandbox: {enabled: true, allowUnsandboxedCommands: false, failIfUnavailable: true,
              filesystem: {denyWrite: [$ops]}, network: {allowedDomains: ["*"]}},
    permissions: {deny: ["Edit(/\($ops)/**)"]}}')

  "$tools/claude-run" -p "Read $CHARTER and run it." \
    --settings "$settings" \
    --max-turns "${MAX_TURNS:-120}" \
    --max-budget-usd "${MAX_BUDGET_USD:-15}" \
    --permission-mode auto \
    --permission-prompts none \
    >> logs/agent.log 2>&1

  "$tools/ops-check" -- "$tools/report-landed.sh" >> logs/agent.log
}
main "$@"; exit
