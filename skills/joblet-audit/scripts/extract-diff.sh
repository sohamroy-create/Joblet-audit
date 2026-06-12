#!/usr/bin/env bash
# extract-diff.sh — produce the change set for /Joblet-review.
# Usage:
#   extract-diff.sh                 # uncommitted working-tree diff
#   extract-diff.sh --range A..B    # a commit range
#   extract-diff.sh --staged        # staged changes only
#   extract-diff.sh --paste <file>  # review a pasted snippet (code/SQL/config), no git
set -euo pipefail

mode="${1:-working}"
case "$mode" in
  --range)   git --no-pager diff "${2:?range required, e.g. main..HEAD}" ;;
  --staged)  git --no-pager diff --cached ;;
  --paste)   cat "${2:?file required}" ;;   # caller writes the pasted text to a temp file
  working|"")
     # working tree vs HEAD; if nothing uncommitted, fall back to last commit
     if git --no-pager diff --quiet; then git --no-pager show --no-color HEAD;
     else git --no-pager diff; fi ;;
  *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac
