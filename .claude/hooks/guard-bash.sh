#!/bin/bash
# Blocks force pushes and any push that names main. --force-with-lease stays allowed,
# because rebasing a PR branch needs it. This is a speed bump: a bare `git push` while
# on main, or a git alias, gets past any regex. Branch protection on the remote is the wall.
set -e
CMD=$(jq -r '.tool_input.command // empty')

if echo "$CMD" | grep -qE 'git( -C [^ ]+)* push.*(--force( |$)| -[a-z]*f[a-z]*( |$)| \+|( |:|refs/heads/)main( |$))'; then
  echo "Blocked: no force pushes and no pushes to main. Open a PR." >&2
  exit 2
fi

exit 0
