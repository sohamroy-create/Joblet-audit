---
name: joblet-audit
description: Joblet PR/code review system. Reviews a git diff (or pasted code/SQL/config) against Joblet-specific findings and anti-patterns using a multi-agent family loop (Checker → Cynic → Researcher), and proposes lessons to a reviewed quarantine. Invoke for the everyday review command /Joblet-review, and the privileged commands /34287 (weekly report), /35398 (apply updates), /46408 (rotate keys), /456098 (change agent logic).
---

# Joblet-Audit — Orchestrator Brain

This skill reviews code changes for the Joblet job-board (Next.js 14 + Supabase/PostgREST + Firebase + KafkaJS + services/embed-service) against the project's own audit history.

## Files in this skill
- `roles/` — the four agent-role prompt templates (checker, cynic, researcher, analyser), parameterized per family.
- `families/` — per-family definitions (glob triggers + seed checklist + role tuning).
- `orchestrator/routing.json` — family → file-glob routing + the generalist fallback.
- `orchestrator/output-contract.md` — the report format.
- `orchestrator/json-schemas.md` — the strict JSON contracts passed between roles.
- `orchestrator/static-checks.md` — deterministic lint pre-pass (no agents).
- `orchestrator/learning-loop.md` — lesson lifecycle + the FAIL→PASS regression-promotion gate (Phase 4).
- `knowledge/source-registry.md` + `knowledge/cache.jsonl` — Researcher source tiers, novelty mode, cached lookups (Phase 3).
- `commands/` — the five command entry points.
- `scripts/` — `extract-diff.sh` (get the change), `corpus-sync.sh` (pull/append corpus).
- The shared corpus lives in the **target repo** at `.joblet-audit/` (NOT in this skill) so it syncs across users via git. See `corpus-sync.sh`.

## Command map (full spec in `agent/COMMAND_SURFACE.md`)
| Command | Tier | Entry file |
|---|---|---|
| `/Joblet-review` | everyone, no key | `commands/Joblet-review.md` |
| `/34287` | reviewers, no key (read-only) → weekly report .docx | `commands/34287.md` |
| `/35398` | Approver key → apply approved updates | `commands/35398.md` |
| `/46408` | Approver key → rotate read-only tokens | `commands/46408.md` |
| `/456098` | Source key (Soham) → change agent logic/source | `commands/456098.md` |

---

## How `/Joblet-review` runs (the default everyday flow)

**Step 1 — Get the change.** Run `scripts/extract-diff.sh` for the change set. Modes:
- default → uncommitted `git diff` (working tree).
- `--range A..B` → that commit range.
- `--paste` → review the code/SQL/config the user pasted (no git).

**Step 2 — Pull the corpus.** Run `scripts/corpus-sync.sh pull`. Load `.joblet-audit/findings.jsonl`, the relevant `checklists/<family>.md`, and recent `lessons.jsonl` (active lessons only).

**Step 3 — Route.** Read `orchestrator/routing.json`. Wake a family if **EITHER** (a) a changed file path matches one of its `globs`, **OR** (b) the diff *content* contains one of its `content_signals` (e.g. `.or(`, `supabaseAdmin`, `select('*')`). Content-signal matching is mandatory — path globs alone miss security/data bugs that live in generically-named files (e.g. `src/lib/userSync.ts`). Over-waking is safe; under-waking is not. **Always also wake the `generalist` family if** any file matches no family, OR the diff deletes code, OR routing is uncertain ("when unsure, wake everything").

**Step 3b — Static pre-pass (no agents).** Before fanning out, run the deterministic lint rules in `orchestrator/static-checks.md` (grep/AST). Their matches go straight into the report with a `[deterministic]` tag (no Checker/Cynic needed — you don't refute a grep hit) and are passed as context to the relevant family Checker. This keeps lint-grade SEO/CSP/`select('*')` checks off the expensive agent path.

**Step 4 — Run families IN PARALLEL** (spike constraint #1). For each woken family, spawn its agents using the Agent/Task tool:
- **FAST mode (default for `/Joblet-review`):** Checker → Cynic only. The Researcher is NOT run by default (it is the slow/expensive tier — spike constraint #3).
- Each Checker uses `roles/checker.md` + the family's `families/<name>.md`. It does TWO passes: (1) checklist (coverage floor), (2) open-ended hunt for new logic errors/bugs (recall-first). Returns the Checker JSON (see `json-schemas.md`).
- Each Cynic uses `roles/cynic.md`, is fed its Checker's JSON **AND the exact diff each finding refers to** (mandatory — added after Phase-3/4 testing; without the diff the Cynic over-refutes real defects by checking the wrong artifact), and returns Cynic verdicts JSON.
- **Researcher fires ONLY when** a Cynic returns `needs-research` for a finding, OR the diff introduces an unfamiliar library/pattern (novelty). Uses `roles/researcher.md`, returns a source-tagged ruling.

**Step 5 — Timeout & partial results** (spike constraint #2). Apply a per-run wall-clock budget (default 6 min). If a role exceeds its slice, drop that finding to `needs-human` and continue — never block the whole report on one hung agent. Note any dropped/timed-out work visibly in the report ("not reviewed" — never silent).

**Step 6 — Merge & dedup** (spike constraint #4). The Orchestrator de-duplicates findings that multiple families raised on the same file:line (e.g. a missing `await` flagged by both Security and Database) and assigns each to the correct family by scope. Keep the highest-confidence framing.

**Step 7 — Emit the report** per `orchestrator/output-contract.md`: severity-graded, `file:line · finding · why · fix · confidence · source-tag · family`. To terminal now (PR comment in the post-MVP Action stage).

**Step 8 — Propose lessons to QUARANTINE only.** Run the Analyser (`roles/analyser.md`) on the run outcome. Any new lesson is **appended as a suggestion to the quarantine** (`.joblet-audit/quarantine.jsonl`) — it is NEVER made active here. `/Joblet-review` has no power to change active corpus, checklists, keys, or agent logic.

## Hard rules (enforced on every run)
- **Knowledge vs behavior:** `/Joblet-review` and `/35398` may only change *what the system knows* (lessons, rules, findings). Any change to *how the system thinks* — agent source, role definitions, routing logic, prompts, the skill structure — requires `/456098` (Source key, held by Soham). If a user attempts such a change without it: refuse and say *"You need the source-change command /456098. If you don't have it, ask Soham."*
- **Privileged-command gating:** `/35398` and `/46408` require the Approver key; `/456098` requires the Source key. Missing/invalid key → refuse with no side effects.
- **`/35398` scope guard:** if an apply-updates run reaches beyond the proposed items in the report, or (at your discretion) makes a fundamental logic change, HALT → require `/456098`.
- **Mark verified / claimed / assumed.** Every Researcher claim must carry a source tier + citation; untagged = assumption, not evidence.
- **Parallel families, JSON contracts, partial-result safety** are not optional — they are the spike-proven constraints.
