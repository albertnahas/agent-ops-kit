#!/bin/bash
# Blocks force pushes and any push that names main. --force-with-lease stays allowed,
# because rebasing a PR branch needs it. It reads only real `git push` commands: heredoc
# bodies are dropped, quotes are unwrapped, and a push must start a command (the start of
# a line or after ; & | ( { or then/do/else). So a PR body or a commit message that mentions
# a push to main passes. This is a speed bump, not a wall: `bash -c`, a script file, a bare
# `git push` while on main or a git alias all get past it. Branch protection on the remote is
# the wall, and private repos on GitHub's free plan don't have it.
set -e
CMD=$(jq -r '.tool_input.command // empty' | awk '
  hd != "" { if ($0 == hd || (strip && sub(/^\t+/, "") && $0 == hd)) hd = ""; next }
  { line = buf $0; buf = "" }
  sub(/\\$/, "", line) { buf = line; next }
  match(line, /(^|[^<])<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/) {
    hd = substr(line, RSTART, RLENGTH); strip = hd ~ /<<-/; sub(/^.*<<-?[ \t]*["\047]?/, "", hd) }
  { gsub(/["\047]/, "", line); print line }')
start='(^|[;&|({]|(then|do|else)[[:space:]])[[:space:]]*'
if echo "$CMD" | grep -qE "${start}git([[:space:]]+-C[[:space:]]+[^[:space:];&|]+)*[[:space:]]+push([[:space:]][^;&|]*)?(--force([[:space:]]|$|;)|[[:space:]]-[a-z]*f[a-z]*([[:space:]]|$)|[[:space:]]\+|([[:space:]]|:|refs/heads/)main([[:space:]]|$|;))"; then
  echo "Blocked: no force pushes and no pushes to main. Open a PR." >&2
  exit 2
fi

exit 0
