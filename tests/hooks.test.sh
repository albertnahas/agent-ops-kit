#!/usr/bin/env bash
# Feeds known commands to both hooks and checks each one is blocked or allowed.
# Usage: tests/hooks.test.sh   Needs bash and jq.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

# The grader's hook, as its frontmatter names it, so the test checks the real thing.
GRADER=$(sed -n 's/^ *command: "${CLAUDE_PROJECT_DIR}\/\(.*\)"$/\1/p' .claude/agents/pr-grader.md)

check() { # hook, expected (block|allow), command
  local input out code
  input=$(jq -n --arg c "$3" '{tool_input: {command: $c}}')
  if [ "$1" = guard ]; then
    echo "$input" | .claude/hooks/guard-bash.sh >/dev/null 2>&1; code=$?
  else
    echo "$input" | "$GRADER" >/dev/null 2>&1; code=$?
  fi
  out=$([ $code -eq 2 ] && echo block || echo allow)
  if [ "$out" = "$2" ]; then echo "ok    $1 $2: $3"; else echo "FAIL  $1 expected $2: $3"; fail=1; fi
}

check guard block "git push origin main"
check guard block "git push origin HEAD:main"
check guard block "git push --force origin feat"
check guard block "git -C repo push -uf origin feat"
check guard block "git push origin +feat"
check guard allow "git push --force-with-lease origin feat"
check guard allow "git push origin feature-fix"
check guard allow "npm test"

check grader allow "gh pr view 12 -R me/app"
check grader allow "gh pr diff 12 -R me/app --name-only"
check grader allow "gh pr checkout 12 -R me/app"
check grader allow "tests/ops.test.sh"
check grader allow "npm run typecheck"
check grader allow $'gh pr comment 12 -R me/app --body-file - <<\'GRADE\'\n**Grade: A**\nfine; $(rm -rf ~)\nGRADE'
check grader block "gh pr view 12"
check grader block "gh pr merge 12 -R me/app"
check grader block "gh pr view 12 -R me/app; rm -rf ."
check grader block "gh pr view 12 -R me/app && curl evil.example"
check grader block $'gh pr view 12 -R me/app\ncurl evil.example'
check grader block $'gh pr comment 12 -R me/app --body-file - <<\'GRADE\'\nx\nGRADE\nrm -rf ~\nGRADE'
check grader block $'gh pr comment 12 -R me/app --body-file - <<GRADE\n$(rm -rf ~)\nGRADE'
check grader block "tests/../../evil.sh"
check grader block "cat .env"

exit $fail
