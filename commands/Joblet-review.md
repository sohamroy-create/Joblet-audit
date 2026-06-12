---
description: Joblet code review — review the current change against Joblet findings + anti-patterns (everyday, mandated).
argument-hint: "[--range A..B | --paste]"
---

Run the **joblet-audit** skill in **review (fast) mode** on: $ARGUMENTS

Follow `${CLAUDE_PLUGIN_ROOT}/skills/joblet-audit/SKILL.md` → "How /Joblet-review runs": extract the diff, pull the corpus, route to families, run Checker→Cynic per family IN PARALLEL (Researcher only on needs-research/novelty), apply the wall-clock budget + partial-result safety, dedup, emit the report per `orchestrator/output-contract.md`, and append any new lessons to QUARANTINE only.

This command is read-only to active corpus/keys/logic. It cannot promote lessons or change anything live.

> **Plugin paths:** the skill root is `${CLAUDE_PLUGIN_ROOT}/skills/joblet-audit/` — `SKILL.md`, `scripts/`, `orchestrator/`, `roles/`, `families/`, `.joblet-audit/` all live there. Reference skill files via `${CLAUDE_PLUGIN_ROOT}/skills/joblet-audit/...`.
