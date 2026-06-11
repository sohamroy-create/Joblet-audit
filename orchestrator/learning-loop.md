# Learning loop (Phase 4)

Turns mistakes into durable improvement WITHOUT touching agent logic. The whole path is: **propose (quarantine) → review (/34287) → promote (/35398, gated by a regression proof)**. Nothing here changes HOW the system thinks (that is `/456098`).

## Lesson lifecycle
1. **Propose.** After a run (and after human accept/reject feedback when available), the Analyser appends a lesson to `.joblet-audit/quarantine.jsonl` (schema in `orchestrator/json-schemas.md`). Two types:
   - `knowledge` — a new/sharpened checklist rule, missed pattern, or corrected severity heuristic.
   - `regression` — a minimal labeled case (bad-diff that should be caught, or good-diff wrongly flagged).
   Feedback rule: only an **explicit accept/reject** counts. An *ignore* is NOT a rejection (stops "devs spam-ignore → real bugs learned as noise").
2. **Review.** `/34287` renders the quarantine as a Word report for a human.
3. **Promote (gated).** `/35398` (Approver key) may make a `knowledge` lesson an active checklist rule **only if** a paired regression case **flips FAIL→PASS** (see gate below). Writes to the canonical corpus with author+timestamp, revertible.

## The regression gate (the proof a lesson actually works)
Each promotable knowledge lesson MUST carry a regression case in `.joblet-audit/regressions/<family>/<id>.json`:
```json
{"id":"<fam>-reg-N","family":"<name>","kind":"should_catch|should_ignore",
 "diff":"<the minimal diff text>","expect":{"min_severity":"P1","claim_contains":"keyword"},
 "origin_lesson":"<quarantine ts>"}
```
Promotion procedure:
- **Before** adding the rule: run the family Checker on the regression `diff`. For a `should_catch` case it must currently **FAIL** (miss it) — otherwise the rule is redundant, reject.
- **After** adding the rule to the checklist: re-run. It must now **PASS** (catch it, ≥ expected severity). FAIL→PASS = proof the lesson changed behavior → promote. Else → do not promote, return to quarantine with a note.
- `should_ignore` cases guard precision: the rule must NOT cause a clean diff to be flagged (PASS = still clean).

## Conflict detection + rollback
- Before promoting, scan active checklist rules for one that contradicts or duplicates the new lesson (`conflicts_with`). On conflict → do not auto-merge; flag for the human in the /34287 report.
- Every promotion is a discrete, timestamped, **revertible** entry. A bad rule can be rolled back (and its regression case kept to prevent re-introduction).

## Anti-bloat (bounded growth)
- Active checklist rules are retrieval-scoped: only rules relevant to the changed files are injected into a Checker (not the whole list), so the prompt does not grow unboundedly.
- Periodic dedup: lessons that subsume older rules replace them (the older rule's regression case is retained).

## Boundary guard
The Analyser may NEVER propose a change to agent source/roles/routing/prompts. If a problem is only fixable by changing HOW the system thinks, the lesson body says so and tags `requires:/456098` — it does not attempt the change.
