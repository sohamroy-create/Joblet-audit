#!/usr/bin/env bash
# corpus-sync.sh — sync the shared knowledge corpus across users via git.
# The canonical corpus is a dedicated branch in the target repo (see config.json:canonical_source).
# Phase 0: implemented for a local .joblet-audit/ ; branch-sync marked where it needs the real repo.
set -euo pipefail

CORPUS_DIR="${JOBLET_AUDIT_CORPUS:-.joblet-audit}"
BRANCH="$(jq -r '.canonical_source.branch' "$CORPUS_DIR/config.json" 2>/dev/null || echo joblet-audit-corpus)"

cmd="${1:-pull}"
case "$cmd" in
  pull)
    # Refresh the active corpus from the canonical branch (read-only).
    if git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
      git fetch origin "$BRANCH" >/dev/null 2>&1 || true
      git --no-pager show "origin/$BRANCH:$CORPUS_DIR/findings.jsonl"  > "$CORPUS_DIR/findings.jsonl"  2>/dev/null || true
      git --no-pager show "origin/$BRANCH:$CORPUS_DIR/lessons.jsonl"   > "$CORPUS_DIR/lessons.jsonl"   2>/dev/null || true
    fi
    echo "corpus pulled (branch: $BRANCH)";;
  propose)
    # Append a quarantine suggestion (append-only → no merge conflicts). $2 = one JSON line.
    printf '%s\n' "${2:?json line required}" >> "$CORPUS_DIR/quarantine.jsonl"
    echo "queued to quarantine";;
  promote)
    # Called ONLY by /35398 after approval+regression pass. $2 = family, $3 = rule line.
    printf '%s\n' "${3:?rule required}" >> "$CORPUS_DIR/checklists/${2:?family required}.md"
    echo "promoted to ${2} checklist (commit to $BRANCH to publish to all users)";;
  *) echo "usage: corpus-sync.sh [pull|propose <json>|promote <family> <rule>]" >&2; exit 2 ;;
esac
