# Learning loop — propose → review → promote

Turns mistakes into durable improvement WITHOUT touching agent logic. The entire path changes **WHAT the system knows**, never **HOW it thinks** (that is `/456098`, source key, held by Soham — SPEC §6.4). Active rules are **retrieval-scoped** so prompts never grow unboundedly.

```
/Joblet-review (Analyser)        /34287 (reviewers, no key)        /35398 (Approver key)
   append → quarantine.jsonl  ──►   render quarantine → .docx   ──►   promote IFF regression FAIL→PASS
   (status:"quarantined")          (read-only)                       (writes active corpus, revertible)
```

## 1. Lifecycle (3 stages + the gates between them)

| Stage | Command / role | Power | Output |
|---|---|---|---|
| **Propose** | `/Joblet-review` → Analyser (`roles/analyser.md`) | quarantine-only, zero power over active corpus | append to `.joblet-audit/quarantine.jsonl`, `status:"quarantined"` |
| **Review** | `/34287` (reviewers, no key) | read-only | quarantine rendered as Word `.docx` for a human |
| **Promote** | `/35398` (Approver key) | apply `knowledge` only, scope-guarded | active checklist rule, author + timestamp, revertible |

**Lesson types** (schema in `orchestrator/json-schemas.md` §4; written with `status:"quarantined"` always):
- `knowledge` — a new/sharpened checklist rule, missed pattern, or corrected severity heuristic. Promotable via `/35398` IFF it carries a regression case that flips FAIL→PASS.
- `regression` — a minimal labeled case (`should_catch` bad-diff, or `should_ignore` good-diff). The proof artifact a `knowledge` lesson is gated on.
- *Behavior-class lessons* are NOT a separate `type` — they are `type:"knowledge"` tagged `requires:"/456098"`. They flag a fix realizable only by changing HOW the system thinks; the Analyser never self-applies them and they are NOT promotable via `/35398` (see §5).

**Feedback rule — ignores are NOT rejections.** Only an **explicit accept/reject** mutates how a lesson is treated. An *ignore* (dev dismisses a finding silently) counts as neither accept nor reject — it never demotes a finding into "noise". This blocks the failure mode where devs spam-ignore real bugs and the system learns them as false positives (SPEC §6.1). The Analyser only proposes after explicit accept/reject when such feedback is available.

## 2. The regression gate (proof a lesson works — FAIL→PASS)

Each promotable `knowledge` lesson MUST carry a case at `.joblet-audit/regressions/<family>/<id>.json` (schema, SPEC §6.2):
```json
{"id":"<fam>-reg-N","family":"<name>","kind":"should_catch|should_ignore",
 "diff":"<minimal diff text>","expect":{"min_severity":"P1","claim_contains":"keyword"},
 "origin_lesson":"<quarantine ts>"}
```

**Procedure (`/35398` runs this before writing the active rule):**

| Step | `should_catch` | `should_ignore` |
|---|---|---|
| **Before** rule added — run family Checker on `diff` | MUST currently **FAIL** (miss it). If it already passes → rule is redundant → **reject**, leave quarantined with a note. | MUST currently be clean (PASS). |
| **After** rule added to checklist — re-run | MUST now **PASS**: catch it AND severity ≥ `expect.min_severity` AND claim contains `expect.claim_contains`. | MUST stay clean (PASS). A new flag = precision regression → **reject**. |
| **Verdict** | **FAIL→PASS = proof** → promote. Else → return to quarantine. | PASS→PASS required; any flip → reject. |

**Canonical example (live in corpus):** the `database` lesson with `trigger_finding:"T8"` — *".limit() with no ORDER BY on a large table is P1, not P2"* (`quarantine.jsonl`, `requires:/35398`; the lesson object has no `id` field) is gated by `.joblet-audit/regressions/database/limit-no-order.json` (`id:"db-reg-1"`, `kind:"should_catch"`, `expect.min_severity:"P1"`, `expect.claim_contains:"ORDER BY"`). The case `diff` selects from `jobs_joveo_partner_v2` with `.limit(500)` and no `ORDER BY`; the rule must make the Checker raise it at ≥ P1 with an "ORDER BY" claim. This severity rule applies in both `database` (D17, `applyLinkChecker.js`) and `cron-reliability` (SPEC §5.2).

## 3. Conflict detection (no silent auto-merge)

Before promoting, scan **active** checklist rules for one that contradicts or duplicates the candidate; record the match in the lesson's `conflicts_with` (else `null`).

| Situation | Action |
|---|---|
| `conflicts_with` is `null` | proceed to the regression gate |
| Candidate **contradicts** an active rule (e.g. different severity for same pattern) | do NOT auto-merge → flag for the human in the `/34287` report; human decides which wins |
| Candidate **subsumes / duplicates** an active rule | mark for replacement (see §4 subsumption), not blind addition |

A conflict NEVER resolves itself; resolution is a human decision surfaced in `/34287`.

## 4. Bounded growth + rollback

**Retrieval-scoped injection (anti-bloat).** Active rules are NOT all dumped into every Checker. At run time only rules whose scope matches the changed files are injected into each family Checker (SPEC §1 Step 2). Prompts stay bounded as the corpus grows — corpus size and prompt size are decoupled.

**Subsumption (dedup).** When a newer lesson subsumes older rules, the older rules are **replaced**, not stacked. The older rule's **regression case is retained** so the superseded bug can never silently re-enter — coverage only ever grows, rule count stays bounded.

**Rollback.** Every promotion is a discrete, timestamped, authored, **revertible** entry in the active corpus. A bad rule can be rolled back; its regression case is **kept** to prevent re-introduction. Removing/adding a static pre-pass rule (`orchestrator/static-checks.md`) is also a `knowledge` change and follows this same revertible path.

## 5. Boundary guard — knowledge vs behavior (the hard line)

| | Knowledge (this loop owns) | Behavior (this loop must NOT touch) |
|---|---|---|
| **What** | lessons, checklist rules, findings, static-pre-pass rule membership, severity heuristics | agent source, `roles/`, routing logic, prompts, the pre-pass *mechanism*, skill structure |
| **Changed by** | `/Joblet-review` (propose to quarantine) + `/35398` (promote, gated) | `/456098` ONLY (source key, Soham) |

- The Analyser may **NEVER** propose a behavior change. If a problem is only fixable by changing how the system thinks, the lesson body says so and tags `requires:"/456098"` — it does NOT attempt the change. Live example: `quarantine.jsonl` carries the `_meta/cynic` artifact-scope lesson with `type:"knowledge"`, `requires:"/456098"`, `status:"quarantined-APPLIED-at-build"` — a behavior-class fix that the loop only *flagged*, never self-applied.
- **Default when ambiguous → BEHAVIOR** (`config.json boundaries.boundary_default:"/456098"`). Knowledge is the narrow, explicitly-scoped case; everything else escalates.
- If a user attempts a behavior change without the source key, refuse with exactly:
  > *"You need the source-change command /456098. If you don't have it, ask Soham."*
- `/35398` carries a matching scope guard: if an apply-updates run reaches beyond the items proposed in the `/34287` report, or makes a fundamental logic change, it HALTs and escalates to `/456098` (SPEC §6.3).

## 6. Invariants

- Analyser writes are **quarantine-only**; `status` is always `quarantined` on write. `/Joblet-review` has zero power to change active corpus, checklists, keys, or agent logic.
- Promotion requires BOTH human approval (`/35398`, Approver key) AND a regression case that flips FAIL→PASS (`config.json promotion_rule`).
- One valid JSON object per line in `quarantine.jsonl` / `lessons.jsonl`; one JSON object per regression file. Malformed → treat as failure, never silent.
