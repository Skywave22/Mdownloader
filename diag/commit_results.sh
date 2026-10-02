#!/usr/bin/env bash
# TEMPORARY: commit a diagnostic job's results (and any regenerated files it names)
# to the branch. Jobs run in parallel, so the push retries after a rebase.
# usage: commit_results.sh "<message>" <paths...>
set -u
msg="$1"; shift
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -f -- "$@" 2>/dev/null
if git diff --cached --quiet; then echo "nothing to commit"; exit 0; fi
git commit -q -m "$msg [skip ci]"
git reset -q --hard HEAD          # drop other build output so the rebase is clean
for i in 1 2 3 4 5 6 7 8; do
  if git pull --rebase -q origin "$GITHUB_REF_NAME" && git push -q origin "HEAD:$GITHUB_REF_NAME"; then
    echo "pushed on attempt $i"; exit 0
  fi
  sleep $((RANDOM % 10 + 3))
done
echo "could not push results"; exit 1
