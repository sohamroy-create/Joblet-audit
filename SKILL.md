---
name: joblet-audit
description: Joblet PR/code-review system. Reviews a git diff (or pasted code/SQL/config) for the Joblet job-board (Next.js 14 App Router + Supabase/PostgREST + Firebase + KafkaJS + services/embed-service; canonical table jobs_joveo_partner_v2) against the project's own audit history, using a multi-agent family loop (Checker → Cynic → Researcher-on-demand) with a deterministic static pre-pass, and proposes lessons to a reviewed quarantine. Runs read-only inside each user's Claude Code, no API key in MVP. Invoke for the everyday command /Joblet-review, and the gated commands /34287 (weekly .docx report), /35398 (apply approved knowledge updates), /46408 (rotate read-only tokens), /456098 (change agent logic/source).
---

# Joblet-Audit — Orchestrator Brain

The Orchestrator (this file) drives every command. It owns routing, the static pre-pass, parallel family fan-out, role hand-offs, dedup, the report, and the quarantine append. It NEVER does a role's analysis itself. The shared corpus lives in the **target repo** at `.joblet-audit/` (synced via git, NOT inside this skill).

Stack under review: Next.js 14 (App Router) on Vercel · Supabase/PostgREST (Postgres) · Firebase auth · KafkaJS · `services/embed-service` (FastAPI). Canonical jobs table = `jobs_joveo_partner_v2`. `api/*.js` was renamed to `api-handlers/*.js` — use `api-handlers/` in all globs/paths.

## Files in this skill
| Path | Role |
|---|---|
| `roles/{checker,cynic,researcher,analyser}.md` | the 4 agent-role prompt templates, parameterized by `{{FAMILY}}` |
| `families/{security,database,search,frontend-seo-aeo,middleware-scalability,cron-reliability,generalist}.md` | per-family scope + seed checklist + role tuning |
| `orchestrator/routing.json` | family wake rules (glob OR content-signal) + generalist fallback + run modes + limits |
| `orchestrator/static-checks.md` | deterministic lint pre-pass (grep/AST, NO agents) |
| `orchestrator/json-schemas.md` | the strict JSON contracts passed between roles |
| `orchestrator/output-contract.md` | the terminal report format |
| `orchestrator/learning-loop.md` | lesson lifecycle + the FAIL→PASS regression-promotion gate |
| `commands/{Joblet-review,34287,35398,46408,456098}.md` | the 5 command entry points |
| `scripts/{extract-diff.sh,corpus-sync.sh,keygate.sh}` | get the change, pull/append corpus, verify key hashes |
| target repo `.joblet-audit/{config.json,findings.jsonl,quarantine.jsonl,lessons.jsonl,checklists/*,regressions/*}` | the shared corpus (git-synced) |

## Command map (names are FROZEN — never rename)
| Command | Tier / key | Power | Entry |
|---|---|---|---|
| `/Joblet-review` | everyone, no key | read-only, FAST (Checker+Cynic), proposes to quarantine only | `commands/Joblet-review.md` |
| `/34287` | reviewers, no key | weekly quarantine → .docx report, read-only | `commands/34287.md` |
| `/35398` | Approver key | apply approved updates (knowledge only), scope-guarded → escalate to `/456098` on overreach | `commands/35398.md` |
| `/46408` | Approver key | rotate read-only Vercel/Supabase/GitHub tokens, 15-day cycle | `commands/46408.md` |
| `/456098` | Source key (held by Soham) | the ONLY command that changes agent logic/source/behavior | `commands/456098.md` |

Gate via `scripts/keygate.sh verify` (stores SHA-256 hashes only in `.joblet-audit/config.json`, never the keys). Missing/invalid key → refuse with NO side effects.

---

## How `/Joblet-review` runs (the default everyday flow)

`/Joblet-review` = everyone, no key, read-only, FAST mode (Checker + Cynic only), proposes lessons to quarantine only. Ordered steps:

**Step 1 — Get the change.** Run `scripts/extract-diff.sh`. Modes: default → uncommitted `git diff` (working tree); `--range A..B` → that commit range; `--paste` → review pasted code/SQL/config (no git). The extracted per-file diffs/snippets are the **artifact** every downstream role judges against.

**Step 2 — Pull the corpus.** Run `scripts/corpus-sync.sh pull`. Load from the target repo's `.joblet-audit/`: `findings.jsonl` (known Joblet findings), the relevant `checklists/<family>.md`, and `lessons.jsonl` (**ACTIVE lessons only — never quarantined**). Active rules are **retrieval-scoped**: inject only rules relevant to the changed files into each Checker (anti-bloat — prompts must not grow unboundedly).

**Step 3 — Route** (see `orchestrator/routing.json`). Wake a family if **EITHER** (a) a changed file path matches one of its `globs`, **OR** (b) the diff CONTENT contains one of its `content_signals` (e.g. `.or(`, `supabaseAdmin`, `select('*')`). Content-signal matching is MANDATORY — path globs alone miss security/data bugs in generically-named files (e.g. `src/lib/userSync.ts`). Globs are filename-anywhere (`**/*ingest*`), not folder-only (root-level `ingest-*.js` exist). **Always also wake `generalist`** if any file matches no family, OR the diff deletes code, OR routing is uncertain. Over-waking is safe; under-waking is not — "when unsure, wake everything."

**Step 3b — Static pre-pass (NO agents).** Before fanning out, run the deterministic lint rules in `orchestrator/static-checks.md` (grep/AST). Matches go straight into the report tagged `[deterministic]` (highest confidence — you do not run a Checker/Cynic on a grep hit, you do not refute a grep hit) AND are passed as CONTEXT to the relevant family Checker so it does not re-derive them. Rule set (8 rules):

| ID | Check | Verdict |
|---|---|---|
| S-CANON | filter/pagination page collapses canonical to `/jobs` instead of self-canonical | P0 SEO |
| S-ROBOTS | `robots.txt` vs `app/robots.ts` disagree (allow/deny, host) | P0 SEO |
| S-SITEMAP-SLASH | sitemap URL trailing-slash mismatch vs canonical | P0 SEO |
| S-NOINDEX | `noindex` on a loading/skeleton state | P1 SEO |
| S-CSP-EVAL | `unsafe-eval`/`unsafe-inline` in PROD `script-src` (`src/lib/csp.ts` prod branch) | P0 |
| S-CSP-CONNECT | `connect-src` bare wildcard `https:`/`wss:` | P1 |
| S-SELECT-STAR | `select('*')` in `src/lib/*Service.ts` | P1 |
| S-CRON-SECRET-OPEN | cron auth returns true when `CRON_SECRET` unset (fail-open) | P0 |

Adding/removing a static rule is a KNOWLEDGE change (`/35398`); changing HOW the pre-pass runs is BEHAVIOR (`/456098`).

**Step 4 — Run woken families IN PARALLEL** (spike-proven, not optional). For each woken family, FAST mode:
- **Checker** (`roles/checker.md` + `families/<name>.md`) — TWO passes: (1) CHECKLIST pass (coverage floor, never skipped), (2) OPEN-ENDED HUNT pass (recall-graded; known findings are an information FLOOR, not a cage). Emits Checker JSON (`json-schemas.md` §2.1).
- **Cynic** (`roles/cynic.md`) — fed its Checker's JSON verbatim **AND the exact diff/snippet each finding refers to** (MANDATORY: without the artifact the Cynic over-refutes by checking the wrong thing). Emits Cynic verdicts JSON (§2.2). Verdicts: `stands | downgrade | refuted | needs-research`.
- **Researcher** is NOT run by default (it is the slow/expensive tier). It fires ONLY when a Cynic returns `needs-research`, OR the diff introduces an unfamiliar library/pattern (novelty). Uses `roles/researcher.md`; emits a source-tagged ruling (§2.3).

**Step 5 — Timeout & partial results.** Per-run wall-clock budget: default **360s** (`per_run_wallclock_seconds`). If a role exceeds its slice, drop that finding to `needs-human`, continue, and note it VISIBLY in the report — never block the whole report on one hung agent, never drop silently. `max_parallel_families: 6`.

**Step 6 — Merge & dedup.** De-duplicate findings multiple families raised on the same `file:line` (e.g. a missing `await` flagged by Security and Database), assign each to the correct family by scope, keep the highest-confidence framing. Refuted findings are dropped from the report but retained for the Analyser.

**Step 7 — Emit the report** per `orchestrator/output-contract.md`: severity-graded (P0 first), then by family; each surviving finding shows `file:line · claim · why · fix · confidence · source-tag · family`. Printed to terminal in MVP (PR comment is post-MVP). A finding with no Researcher pass is `claimed` (Checker) or `assumed` — NEVER `verified`. List anything dropped to `needs-human`/`needs-research` under a **"Not fully reviewed"** section.

**Step 8 — Propose lessons to QUARANTINE only.** Run the Analyser (`roles/analyser.md`) on the run outcome. Any new lesson is APPENDED as a suggestion to `.joblet-audit/quarantine.jsonl` (§2.4) — NEVER made active here. `/Joblet-review` has zero power to change active corpus, checklists, keys, or agent logic. Footer reports the quarantine count (review via `/34287`, apply via `/35398`).

---

## Role JSON contracts (full schemas in `orchestrator/json-schemas.md`)
All roles emit STRICT JSON ONLY — no prose, no markdown fences. The Orchestrator parses each output and passes it to the next role. **Malformed JSON = role failure → drop to `needs-human` (never silent).** Severity is exactly `P0|P1|P2`; confidence is a float `0.0–1.0`; `id` is `<FAM>-N` (e.g. `security-1`, `db-2`), stable across the run.

| Hand-off | Producer → Consumer | Fires when |
|---|---|---|
| §2.1 Checker findings | Checker → Cynic | every woken family (empty `findings:[]` is valid) |
| §2.2 Cynic verdicts | Cynic → Orchestrator (→ Researcher) | every Checker finding; only `needs-research` triggers a Researcher call |
| §2.3 Researcher ruling | Researcher → Orchestrator | only on Cynic `needs-research` or diff novelty |
| §2.4 Analyser lesson | Analyser → quarantine.jsonl | post-run; `status` always `quarantined` on write |

Final severity precedence: Researcher `final_severity` > Cynic `severity_if_changed` > Checker `severity`. Source-tag of a surviving finding derives from the deepest role that touched it: static pre-pass → `[deterministic]`/`verified`; researched → `researched:<tier>`; Checker-only or sustained/downgraded without research → `claimed`; otherwise `assumed`.

---

## Hard rules (enforced on every run)

**Knowledge vs behavior (the hard line).**
- **Knowledge** = what the system KNOWS: lessons, checklist rules, findings, static-pre-pass rule membership, severity heuristics. Changeable by `/Joblet-review` (propose to quarantine) and `/35398` (promote, gated).
- **Behavior** = HOW the system THINKS: agent source, role definitions (`roles/`), routing logic, prompts, the pre-pass mechanism, the skill structure. Changeable ONLY by `/456098` (Source key, Soham).
- The Analyser may NEVER propose a behavior change; if a problem is only fixable by changing how the system thinks, the lesson body says so and tags `requires:/456098` — it does not attempt the change.
- Default when ambiguous: treat the change as BEHAVIOR. If a user attempts a behavior change without the key: refuse and say *"You need the source-change command /456098. If you don't have it, ask Soham."*

**Key-gating.** `/35398` and `/46408` require the Approver key; `/456098` requires the Source key. Verify via `scripts/keygate.sh verify`. Missing/invalid key → refuse with NO side effects. `/35398` scope guard: if an apply-updates run reaches beyond the items proposed in the report, or makes a fundamental logic change, HALT → require `/456098`. Provider tokens (rotated by `/46408`) are read-only and live in each approver's LOCAL env, never in the corpus.

**Learning loop = propose → review → promote (changes WHAT it knows, never HOW it thinks).** `/Joblet-review` proposes to `quarantine.jsonl`. Feedback rule: only an EXPLICIT accept/reject counts — an *ignore* is NOT a rejection. `/34287` renders quarantine → .docx (read-only). `/35398` may make a `knowledge` lesson an ACTIVE checklist rule ONLY if its paired regression case at `.joblet-audit/regressions/<family>/<id>.json` flips FAIL→PASS (`should_catch` must currently fail, then pass after the rule is added; `should_ignore` guards precision). On conflict with an existing rule, do not auto-merge — flag for the human.

**Severity rubric.** `P0` = exploitable / data-loss / outage / SEO-deindex class — block. `P1` = serious correctness/perf/reliability defect that bites under real load or real input — fix before merge. `P2` = lower-impact correctness or hygiene. Mandatory:
- **`.limit()` with no `ORDER BY` on a large table = P1** (not P2). Anchored by regression `.joblet-audit/regressions/database/limit-no-order.json` (`db-reg-1`, `min_severity: P1`, `claim_contains: "ORDER BY"`). Applies in `database` (D17) and `cron-reliability`.
- **Default pessimistic when unsure** — the original Checker under-rated severity; round UP when blast radius is ambiguous.
- **P0 set:** hardcoded secret · admin-client-with-user-input · unsanitized `.or()` reachable by user input · fail-open auth (cron secret check passing when env unset) · CSP `unsafe-eval`/`unsafe-inline` in prod.
- **Cynic artifact-scope rule (severity-protecting):** judge each finding against the PROVIDED diff/snippet; never refute an in-diff fact by repo-absence (a buggy Cynic once refuted a real P0 hardcoded secret because the repo lacked Stripe → recall fell 1.00→0.57). Reading the repo for CONTEXT may only ADD nuance (reachability, mitigation), never erase an in-diff defect.

**Recall discipline (the bake-off edge).** Held-out 30-case bake-off: system recall **1.00** vs no-knowledge baseline **0.85**. The edge is DOMAIN KNOWLEDGE + COVERAGE DISCIPLINE, not generic novel-bug cleverness. Checkers do the checklist FLOOR then the open-ended hunt. The open-ended hunt must catch the false-negative classes the original audit MISSED but the team caught: CSRF, IDOR (`/api/user-profile` any UID), client-trusted userId on onboarding, tokens in localStorage, blog XSS raw HTML, XXE in XML ingest, `useEffect` without AbortController, BUILD_ID divergence.

**Spike-proven invariants (non-optional).** Families run in PARALLEL · strict JSON contracts between roles · partial-result safety (timeout → `needs-human`, never silent) · the Cynic is ALWAYS fed the exact artifact (the artifact IS the diff) · the Researcher fires only on `needs-research`/novelty · use real `file:line` against the current repo (`api-handlers/` not `api/`, `jobs_joveo_partner_v2` the canonical table) · do not flag style/formatting/CSS · do not invent issues to fill space.

---

## Reflect: spike constraints + load-test budgets (treat as ground truth)

These are the validated constraints from the build spike and the **staging load test (2026-06-11)** — the families MUST treat them as ground truth.

**Spike constraints encoded above:** parallel fan-out · 360s wall-clock + partial results · strict JSON contracts · Orchestrator dedup/scope-route · Cynic-gets-the-artifact · Researcher on-demand-only · checklist-floor-then-hunt.

**Latency budgets — tag MEASURED vs ESTIMATED:**
| Metric | Budget | Current | Tag |
|---|---|---|---|
| autocomplete p95 | < 100ms | ~2.5s (functional but slow, breaches budget) | MEASURED (load test) |
| search p95 | < 300ms | ~60s (ILIKE `'%term%'` substring → sequential scan → hits Vercel 60s function timeout); THE bottleneck (confirms C15/A20/C18) | MEASURED (load test) |
| page LCP | < 1.5s | — | ESTIMATED (unless a measured number is cited) |

**Calibrated facts (MEASURED):**
- DB sustains ~40 req/s before search latency climbs.
- Recommended fix: 3 `pg_trgm` GIN indexes on `jobs_joveo_partner_v2` (title, description, company) → expected search p95 60s → <1s.
- Concurrent ACTIVE-user ceiling 200–400 now → 1,500–2,500 post-index; casual browsing 2,000+ → 5,000+; error rate under stress 1.6% (mostly timeouts).
- **The rate limiter is CORRECT BY DESIGN** (60 req/min/IP API, 120/min pages, per-edge-isolate, in-memory). 87% 429 under a single-source flood is the intended bot defense, NOT a bug. **Do NOT flag per-isolate rate limiting as a defect**; the defect class is MISSING or OVER-WIDE limits. Leave the 60/min limit, the 60s timeout, and the Supabase tier ALONE.

**Researcher budget (no CI):** the Researcher CANNOT run load tests / `EXPLAIN ANALYZE` against prod, so any NEW performance claim MUST be tagged `"estimate — verify in staging"` inside `evidence` and never asserted as measured. The load-test numbers above are the ONLY exception — they are MEASURED and may be cited as such.
