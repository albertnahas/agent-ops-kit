#!/bin/bash
# The grader's only Bash: read a PR, check it out, run its tests, post one grade comment. Every gh call names
# its repo with -R, so a grader started in another checkout can't grade the wrong repo's PR with that number.
# The test commands run the PR's code: the sweep runs `mission-guard author` first, so only collaborators' code
# runs. Edit the test line for your stack.
CMD=$(jq -r '.tool_input.command // empty')
R='-R [A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+'
first=${CMD%%$'\n'*}
[[ $CMD =~ ^gh\ pr\ (view|diff|checks)\ [0-9]+\ $R(\ [-a-z0-9=,]+)*$ ]] ||
[[ $CMD =~ ^gh\ pr\ checkout\ [0-9]+\ $R$ ]] ||
[[ $CMD =~ ^(bash\ )?tests/[A-Za-z0-9_.-]+\.sh$ || $CMD =~ ^npm\ (test|run\ [a-z:-]+)$ ]] ||
{ [[ $first =~ ^gh\ pr\ comment\ [0-9]+\ $R\ --body-file\ -\ \<\<\'GRADE\'$ && $CMD == *$'\n'GRADE ]] &&
  [ "$(grep -c '^GRADE$' <<<"${CMD#*$'\n'}")" = 1 ]; } ||
{ echo "The grader only runs gh pr view, diff, checks, checkout and one comment (each with -R owner/repo), and the tests" >&2; exit 2; }
