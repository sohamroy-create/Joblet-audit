# Joblet-Audit — Product Documentation

*A self-hosted, multi-agent code-review system for the Joblet job-board, calibrated against the project's own audit history and a staging load test.*

**Status:** Phase 0 scaffold (mechanics spike-proven; Security + Database families seeded, the rest stubbed). **Corpus snapshot:** repo HEAD `acaf775`, verified 2026-06-11. **Stack under review:** Next.js 14 (App Router) on Vercel · Supabase/PostgREST (Postgres) · Firebase auth · KafkaJS · `services/embed-service` (FastAPI). Canonical jobs table: `jobs_joveo_partner_v2`.

---

## Table of contents

1. [Scope](#1-scope)
2. [Capabilities](#2-capabilities)
   - 2.1 [The review flow](#21-the-review-flow-jobletreview)
   - 2.2 [The 7 families and what each catches](#22-the-7-families)
   - 2.3 [The 4 roles and how they interact](#23-the-4-roles)
   - 2.4 [The static pre-pass](#24-the-static-pre-pass)
   - 2.5 [The learning loop](#25-the-learning-loop)
   - 2.6 [The 5 commands and key tiers](#26-the-5-commands-and-key-tiers)
   - 2.7 [Load-test-calibrated thresholds](#27-load-test-calibrated-thresholds)
3. [Structure](#3-structure)
   - 3.1 [Repo / file layout](#31-repo--file-layout)
   - 3.2 [The corpus](#32-the-corpus)
   - 3.3 [Routing](#33-routing)
   - 3.4 [The JSON contracts](#34-the-json-contracts)
   - 3.5 [Install and team sync](#35-install-and-team-sync)
4. [Evidence and limitations](#4-evidence-and-limitations)

---

## 1. Scope

### What the system is

Joblet-Audit is a **PR / code-review assistant** packaged as a Claude Code skill. You point it at a change — an uncommitted working-tree diff, a commit range, or a pasted snippet of code/SQL/config — and it returns a severity-graded report of defects: P0 (block), P1 (fix before merge), P2 (hygiene).

What makes it more than a generic linter is that it reviews the change **against the Joblet project's own accumulated audit history**. It carries a corpus of known findings, anti-patterns, and root-cause lessons specific to this codebase, plus thresholds calibrated by a real staging load test. It runs a **multi-agent loop** per relevant domain: a Checker hunts for bugs, an adversarial Cynic tries to refute each one, and an on-demand Researcher settles disputes that need an external fact. A deterministic grep/AST pre-pass handles the mechanical, single-right-answer checks before any agent runs.

It runs **entirely inside each developer's local Claude Code, read-only by default, with no Claude API key required** in the MVP.

### Who uses it

- **Every developer**, on every change, via the everyday command `/Joblet-review`. No key, read-only, fast.
- **Reviewers**, who run the weekly report (`/34287`) to see what the system has proposed learning.
- **Approvers** (the reviewer(s)), who hold the **Approver key** and can promote vetted lessons into the active rule set (`/35398`) and rotate provider tokens (`/46408`).
- **Soham** alone, who holds the **Source key** and is the only person who can change *how the system thinks* (`/456098`).

### The problem it solves

The original one-shot audit of Joblet **missed entire classes of real bugs** that the team later caught by hand — CSRF, IDOR, client-trusted user IDs, tokens in `localStorage`, blog XSS via raw HTML, XXE in XML ingest, `useEffect` without an AbortController, BUILD_ID divergence — and it **under-rated severity** and **asserted performance it never measured**. (These failures are catalogued as root causes RC1–RC8 in `.joblet-audit/root-causes.md`.) Joblet-Audit exists to stop those misses from recurring and to keep getting sharper: it bakes the missed classes into a recall-graded hunt, forces every finding through an adversarial second opinion, grounds performance claims in a measured load test, and turns each new mistake into a reviewed, regression-gated rule.

### What it explicitly does NOT do

- **It does not change live code.** It reports; humans fix.
- **`/Joblet-review` has zero power over the active corpus, checklists, keys, or agent logic.** It can only *propose* lessons to a reviewed quarantine.
- **It does not learn autonomously.** A lesson becomes active only after explicit human approval **and** a regression case that flips FAIL→PASS. An *ignore* is never treated as a rejection.
- **It does not flag style, formatting, CSS, or pure renames.** An empty result is a valid, correct answer; it never invents findings to fill space.
- **It does not run load tests, `EXPLAIN ANALYZE`, or hit prod.** There is no CI tier. Any *new* performance claim must be tagged `"estimate — verify in staging"`; only the 2026-06-11 load-test numbers may be cited as measured.
- **It does not flag the rate limiter, the 60s function timeout, or the Supabase tier as defects** — these are calibrated correct-by-design.
- **It does not let knowledge changes drift into behavior changes.** Anything that would alter *how the system thinks* is gated behind the Source key, and when in doubt the system treats a change as behavior.
- **In the MVP it prints to the terminal** — posting findings as PR comments is post-MVP.

---

## 2. Capabilities

### 2.1 The review flow (`/Joblet-review`)

The Orchestrator (defined in `SKILL.md`) drives every command. It owns routing, the static pre-pass, parallel fan-out, role hand-offs, dedup, the report, and the quarantine append — and it **never does a role's analysis itself**. The default everyday flow is eight ordered steps:

1. **Get the change.** `scripts/extract-diff.sh` produces the artifact. Default = uncommitted working-tree diff; `--range A..B` = a commit range; `--staged` = staged changes; `--paste <file>` = a pasted snippet with no git. The extracted per-file diffs/snippets are the **artifact** every downstream role judges against.
2. **Pull the corpus.** `scripts/corpus-sync.sh pull` loads the target repo's `.joblet-audit/`: known findings, the relevant per-family checklists, and **active lessons only — never quarantined ones**. Active rules are **retrieval-scoped**: only rules relevant to the changed files are injected into each Checker, so prompts stay bounded as the corpus grows.
3. **Route** (per `orchestrator/routing.json`). A family wakes if **EITHER** a changed file path matches one of its globs **OR** the diff content contains one of its content signals. Content-signal matching is mandatory — path globs alone miss bugs in generically-named files (e.g. `src/lib/userSync.ts`). The `generalist` family **always also wakes** on an unclaimed file, a code deletion, or routing uncertainty. The rule is *"when unsure, wake everything"* — over-waking is safe; under-waking is not.
3b. **Static pre-pass** (no agents). The deterministic grep/AST rules run first; hits go straight into the report tagged `[deterministic]` (highest confidence) and are handed to the relevant Checker as context so it does not re-derive them.
4. **Run woken families in parallel** (spike-proven). Each family runs **Checker → Cynic** in FAST mode; the **Researcher fires only on a `needs-research` verdict or diff novelty**.
5. **Timeout and partial results.** Per-run wall-clock budget is **360s**; `max_parallel_families` is 6. If a role exceeds its slice, its finding drops to `needs-human`, the run continues, and it is noted **visibly** in the report — never blocked, never dropped silently.
6. **Merge and dedup.** Findings raised by multiple families on the same `file:line` (e.g. a missing `await` flagged by both Security and Database) are de-duplicated, assigned to the scope-correct owner, and the highest-confidence framing is kept. Refuted findings are dropped from the report but retained for the Analyser.
7. **Emit the report** (per `orchestrator/output-contract.md`): severity-graded (P0 first), then by family; each line shows `file:line · claim · why · fix · confidence · source-tag · family`. A finding with no Researcher pass is `claimed` or `assumed` — **never `verified`** (only the deterministic pre-pass earns `verified`). Anything dropped to `needs-human` / `needs-research` is listed under a **"Not fully reviewed"** section.
8. **Propose lessons to quarantine only.** The Analyser runs on the outcome and appends any new lesson to `quarantine.jsonl` as a suggestion (`status:"quarantined"`). The footer reports the quarantine count and points to `/34287` (review) and `/35398` (apply).

### 2.2 The 7 families

Six specialist domain lenses plus a generalist safety net. Each family ships a scope, wake rules, a seed checklist (the coverage *floor*), and an open-ended *hunt* (recall-graded). Severities are exactly **P0 | P1 | P2** — there is no P3.

| # | Family | Lens | Representative findings it catches (real anchors, HEAD `acaf775`) |
|---|---|---|---|
| 1 | **security** | secrets, auth/authz, injection, data exposure, XSS/XXE/CSRF/IDOR, token handling | **E14 (P0):** unsanitized PostgREST `.or()` built from user input via the service-role client in `src/lib/supabase.ts:187` `saveUserToSupabase` → account-takeover (the autocomplete sibling was fixed; this one was not). **29.2.4 (P0):** onboarding handlers (`api-handlers/onboarding/recruiter.js:8`) trust a client `userId` from `req.body` with no token verify → any caller binds a profile to an arbitrary user. **29.7.1 (P0):** blog body rendered via `dangerouslySetInnerHTML` with no sanitizer → stored XSS. **29.2.2 (P1):** auth token read from a URL query and written to `localStorage` (`AuthCallback.tsx`). |
| 2 | **database** | correctness, idempotency, safety of Postgres/PostgREST reads & writes | **D17/db-2 (P1):** `.limit()` with no `ORDER BY` on the candidate pool in `applyLinkChecker.js` → arbitrary slice, stale rows never revisited. **db-1 (P0):** `ILIKE '%term%'` substring filters on the canonical table with the trgm-index migration unapplied in prod → seq scan → search p95 ~60s. **db-3 (P2):** ref-less jobs get a fresh random id every ingest → non-idempotent duplicate rows. **D9/E6:** `select('*')` over-fetch on service-role reads → PII / `password_hash` over the wire. |
| 3 | **search** | search / autocomplete / suggestion correctness, relevance, and search-path latency | **search-1/3 (P0):** `description ILIKE '%term%'` with no trgm index (`advanced-search.js:120`) and an **unsanitized `.or()`** built from the raw user query in the *active* suggestion path (`consolidated-queries.js:31`). **C12 (P1):** `diversifyByCompany` runs a `Math.random()` shuffle **after** the DB relevance sort, randomizing rank order. **(P1):** `.limit(200)` with no `.order()` on suggestions. The safe sanitized sibling endpoint exists but is **not wired up**. |
| 4 | **frontend-seo-aeo** | SEO/AEO correctness + frontend logic hygiene, with a deterministic/agent split (see below) | **F4 (P1):** JSON-LD on the `/jobs` listing serialized with no `</script>` escape, embedding untrusted partner-feed text → stored XSS on a crawlable page (the job-*detail* builder escapes; the listing does not). **F1 (P1):** CSP `connect-src` opens with `'self','https:','wss:'` before granular hosts → wildcards make the allowlist moot. **F7 (P2):** `useEffect` fetch with no AbortController → stale-overwrites-fresh race. |
| 5 | **middleware-scalability** | middleware, caching, connection pooling, frontend↔backend scalability | **MS-1 (P2):** DB-heavy crons run on the default function timeout with no `maxDuration` while regional siblings get 60s. **MS-2 (P2):** middleware matcher excludes `.xml/.json/.txt`, so force-dynamic SEO routes bypass the limiter (CDN-mitigated). **MS-3 (P2):** a divergent dead Express limiter (30/min). The **defect class is MISSING or OVER-WIDE limits** — not the existence of a limit. |
| 6 | **cron-reliability** | cron handlers, self-healing workers, scheduler correctness, operational safety | **#1/D14 (P1):** `serviceProbe.js:37` treats 4xx as healthy (`status >= 200 && < 500`) → a blocked dependency shows green. **#9 (P0):** fail-open SEO-cron auth — `isAuthorized()` returns `true` on the spoofable `x-vercel-cron` header and when the secret is unset; one handler has no auth at all. **#6 (P0):** a destructive deactivation worker whose kill-switch is OFF in prod → a bad feed can mass-deactivate. **#3/D16 (P1):** the run-logger silently loses the run record on insert failure. |
| 7 | **generalist** | fallback recall safety-net — no checklist, pure open-ended hunt | Catches the team-caught / audit-missed classes regardless of domain when no specialist wakes: deleted guards/`await`/auth checks, IDOR, CSRF, `localStorage` tokens, raw-HTML XSS, XXE, `useEffect` races, BUILD_ID divergence. **Guarantee: no PR ever passes with zero families awake.** |

Each Checker does two mandatory passes in order: the **checklist pass** (the coverage floor — it guarantees the project never regresses on a bug it already paid to learn) and the **open-ended hunt** (the false-negative defense — known findings are an information *floor*, not a *cage*). The split between deterministic SEO and the agent-driven frontend-logic lens (the "D1/D2 split") is what keeps `frontend-seo-aeo` precise: mechanical SEO checks go to the static pre-pass; runtime-consequence judgment goes to the agent loop; AEO is advisory-only and never graded.

### 2.3 The 4 roles

All roles are prompt templates in `roles/`, parameterized by `{{FAMILY}}`, and **emit strict JSON only**. Malformed JSON is treated as role failure and the finding drops to `needs-human`.

| Role | Job | Fires | Key discipline |
|---|---|---|---|
| **Checker** | The recall engine. Two passes: checklist floor, then open-ended hunt. Surfaces findings; biases toward surfacing, not suppressing — a missed real bug is the expensive failure. | Every woken family. | Cite real `file:line`; default pessimistic on severity; never invent issues. |
| **Cynic** | The adversarial refuter. Attacks each Checker finding and tries to break it. Verdicts: `stands` / `downgrade` / `refuted` / `needs-research`. | Every Checker finding. | **Always fed the exact diff/snippet** the finding refers to (mandatory). |
| **Researcher** | The slow/expensive evidence tier. Replaces assumptions with source-tagged evidence across four tiers: `our-code` → `canonical-docs` → `current-practice` → `frontier`. Its `final_severity` overrides Checker and Cynic. | **Only** on a Cynic `needs-research` verdict or diff novelty. | No CI: any new perf claim is tagged `"estimate — verify in staging"`. |
| **Analyser** | The meta-learner. Runs last; converts the run's mistakes into a *proposed* lesson (`knowledge` or `regression`). | Post-run. | Writes to **quarantine only**, `status` always `quarantined`; may **never** propose a behavior change. |

**How they interact:** `Checker → (Orchestrator) → Cynic → (Orchestrator, only on needs-research) → Researcher → (Orchestrator) → Analyser`. The Cynic is the second opinion that catches single-pass reasoning errors (RC8); the Researcher is the rarely-fired tie-breaker that grounds the one external fact a dispute hinges on; the Analyser closes the loop by proposing what the system should have known.

**The load-bearing Cynic rule — artifact-scope.** The Cynic must judge each finding against the *provided diff/snippet*, **never refute an in-diff fact by repo-absence**. This rule exists because a buggy Cynic once refuted a real P0 hardcoded secret on the grounds that the wider repo lacked a payment flow — and recall collapsed from **1.00 to 0.57**. Reading the surrounding repo may only *add* nuance (reachability, mitigation); it may never *erase* a defect plainly present in the diff. This is baked into the Cynic role itself, which is why fixing it would be a *behavior* change requiring the Source key.

### 2.4 The static pre-pass

Before any agent runs, eight deterministic grep/AST rules run as a lint-grade pre-pass. Each has a single right answer, never consumes a Checker/Cynic call, and **you do not refute a grep hit**. Matches are emitted to the report tagged `[deterministic]` (highest confidence, `verified`) and handed to the relevant family Checker as context so it does not waste a slot re-deriving them.

| ID | Check | Verdict |
|---|---|---|
| S-CANON | filter/pagination page collapses canonical to `/jobs` instead of self-canonical | P0 SEO |
| S-ROBOTS | `public/robots.txt` vs `app/robots.ts` disagree (allow/deny, host) | P0 SEO |
| S-SITEMAP-SLASH | sitemap URL trailing-slash mismatch vs canonical | P0 SEO |
| S-NOINDEX | `noindex` on a loading/skeleton state | P1 SEO |
| S-CSP-EVAL | `unsafe-eval`/`unsafe-inline` in the PROD `script-src` | P0 |
| S-CSP-CONNECT | `connect-src` bare wildcard `https:`/`wss:` | P1 |
| S-SELECT-STAR | `select('*')` in `src/lib/*Service.ts` | P1 |
| S-CRON-SECRET-OPEN | cron auth returns truthy when its secret env is unset (fail-open) | P0 |

Against the current tree, **S-CSP-CONNECT and S-SELECT-STAR are live matches** (E4 and E6 are open); the rest are regression detectors guarding already-fixed defects, firing only on a new divergence. Adding or removing a rule from this set is a **knowledge** change (`/35398`, regression-gated); changing *how* the pre-pass runs (the mechanism, ordering, tagging) is **behavior** (`/456098`).

### 2.5 The learning loop

The loop changes **WHAT the system knows, never HOW it thinks**, and never autonomously:

```
/Joblet-review (Analyser)        /34287 (reviewers, no key)        /35398 (Approver key)
  append → quarantine.jsonl  ──►   render quarantine → .docx   ──►   promote IFF regression FAIL→PASS
  (status:"quarantined")           (read-only)                       (writes active corpus, revertible)
```

- **Propose.** The Analyser appends a `knowledge` or `regression` lesson to `quarantine.jsonl` — quarantine-only, zero active power.
- **Review.** `/34287` renders the whole quarantine queue as a Word `.docx` for a human, read-only.
- **Promote.** `/35398` (Approver key) can make a `knowledge` lesson an active checklist rule **only if** its paired regression case at `.joblet-audit/regressions/<family>/<id>.json` **flips FAIL→PASS**: the `should_catch` case must currently be *missed*, then be caught at ≥ the expected severity with the expected claim keyword once the rule is added; any `should_ignore` case must stay clean (guarding precision). On conflict with an existing rule, the system does **not** auto-merge — it flags it for the human.

Guardrails that make the loop safe:
- **Ignores are not rejections.** Only an explicit accept/reject mutates how a lesson is treated. This blocks the failure mode where developers spam-ignore real bugs and the system learns them as noise.
- **Bounded growth.** Active rules are retrieval-scoped (only relevant rules are injected per run), and a newer lesson that subsumes older rules *replaces* them while *retaining* the old regression case — so coverage only ever grows but rule count and prompt size stay bounded.
- **Revertible.** Every promotion is a discrete, authored, timestamped, revertible corpus entry; a bad rule can be rolled back, and its regression case is kept to prevent re-introduction.

The canonical live example: the `database` lesson *".limit() with no ORDER BY on a large table is P1, not P2"* is gated by `db-reg-1`, whose `should_catch` diff selects from `jobs_joveo_partner_v2` with `.limit(500)` and no `ORDER BY` and demands the Checker raise it at ≥ P1 with an "ORDER BY" claim.

### 2.6 The 5 commands and key tiers

Command names are **frozen — never renamed**.

| Command | Tier / key | Power |
|---|---|---|
| `/Joblet-review` | everyone, no key | Read-only, FAST (Checker + Cynic). Reviews the change; proposes lessons to quarantine only. Changes nothing live. |
| `/34287` | reviewers, no key | Renders the quarantine queue → a weekly `.docx` report. Read-only. |
| `/35398` | **Approver key** | Applies approved **knowledge** updates, scope-guarded. Promotes a lesson only if its regression flips FAIL→PASS. Escalates to `/456098` on overreach. |
| `/46408` | **Approver key** | Rotates the read-only Vercel/Supabase/GitHub provider tokens on a 15-day cycle; blocks until rotation when overdue. |
| `/456098` | **Source key (Soham only)** | The **only** command that changes agent logic/source/behavior: role definitions, routing, prompts, the pre-pass mechanism, the skill structure, the command surface. |

**Key model.** Privileged commands are gated by a SHA-256 hash stored in `.joblet-audit/config.json` — the **secret keys themselves are never stored**, only their hashes (`scripts/keygate.sh`). A missing or invalid key → refuse with **no side effects**. The denial for `/456098` tells the user: *"You need the source-change command /456098. If you don't have it, ask Soham."* This is an honest **shared-secret gate**, not password-grade crypto; the real control is *who holds the key* plus *who has write access to the corpus branch*. Read-only provider tokens are least-privilege and live in each approver's **local** env — never in the corpus.

**The hard line — knowledge vs behavior.** *Knowledge* = what the system knows (lessons, checklist rules, findings, static-rule membership, severity heuristics) → changeable via `/35398`. *Behavior* = how the system thinks (agent source, roles, routing, prompts, the pre-pass mechanism, structure) → changeable **only** via `/456098`. When a change is ambiguous, the system **defaults to treating it as behavior**. `/35398` carries a scope guard: if an apply run reaches beyond the proposed items or makes a fundamental logic change, it HALTs and escalates.

### 2.7 Load-test-calibrated thresholds

The numbers below are **MEASURED** in the staging load test (2026-06-11) and are treated as ground truth. They are the **only** performance figures any role may cite as fact; every other perf claim must be tagged `"estimate — verify in staging"`.

| Metric | Budget | Measured current | Tag |
|---|---|---|---|
| search p95 | < 300ms | **~60s** — `ILIKE '%term%'` substring → sequential scan → hits the Vercel 60s function timeout. **THE bottleneck** (confirms C15/A20/C18). | MEASURED |
| autocomplete p95 | < 100ms | **~2.5s** — functional but slow. | MEASURED |
| page LCP | < 1.5s | — | **ESTIMATED** |
| DB throughput | — | sustains **~40 req/s** before search latency climbs. | MEASURED |
| active-user ceiling | — | 200–400 now → 1,500–2,500 post-index; casual browse 2,000+ → 5,000+. | MEASURED |
| error rate under stress | — | 1.6% (mostly timeouts). | MEASURED |

**The recommended fix:** 3 `pg_trgm` GIN indexes on `jobs_joveo_partner_v2` (title, description, company), expected to take search p95 from ~60s to **<1s**. *(Implementation note: the on-disk migration `scripts/migrations/add_jobs_listing_search_indexes.sql` currently ships title/company/location/industry/jobType but **omits the description trgm index** — the missing piece the load test recommends.)*

**Correct by design — do NOT flag.** The per-edge-isolate, in-memory rate limiter (60 req/min/IP API, 120/min pages) is intended bot defense — 87% `429` under a single-source flood is the *feature*, not a bug. The 60s function timeout and the Supabase tier are likewise sanctioned. The **defect class is MISSING or OVER-WIDE limits**, never the existence of a limit. Leave the 60/min limit, the 60s timeout, and the Supabase tier alone.

---

## 3. Structure

### 3.1 Repo / file layout

The skill package and the shared corpus are deliberately separate: the **skill** is distributed as a Claude Code plugin; the **corpus** (`.joblet-audit/`) ships into the *target* repo and syncs via git.

```
joblet-audit-skill/                  # the distributable skill (plugin)
  SKILL.md                           # the Orchestrator brain — how a review runs
  README.md / KEY_SETUP.md           # package overview + one-time key setup
  commands/                          # 5 entry points
    Joblet-review.md  34287.md  35398.md  46408.md  456098.md
  roles/                             # 4 agent-role templates, {{FAMILY}}-parameterized
    checker.md  cynic.md  researcher.md  analyser.md
  families/                          # 7 family defs (scope + globs + seed checklist + tuning)
    security.md  database.md  search.md  frontend-seo-aeo.md
    middleware-scalability.md  cron-reliability.md  generalist.md
  orchestrator/
    routing.json                     # family wake rules + run modes + limits + measured facts
    static-checks.md                 # the 8-rule deterministic pre-pass
    json-schemas.md                  # strict inter-role JSON contracts
    output-contract.md               # the terminal report format
    learning-loop.md                 # lesson lifecycle + FAIL→PASS promotion gate
  knowledge/                         # Researcher grounding
    source-registry.md               # the 4-tier source model + family→source map
    cache.jsonl                      # cached tie-break lookups (keyed by question-hash)
  scripts/
    extract-diff.sh                  # get the change (working / range / staged / paste)
    corpus-sync.sh                   # pull / propose / promote against the corpus branch
    keygate.sh                       # set / verify / status of key hashes (SHA-256 only)

.joblet-audit/                       # SHARED CORPUS — ships to the TARGET repo, git-synced
  config.json                        # corpus version, families, run limits, key HASHES, boundaries
  findings.jsonl                     # known Joblet findings (open / fixed / team-fixed)
  lessons.jsonl                      # ACTIVE promoted lessons (empty in Phase 0)
  quarantine.jsonl                   # proposed lessons awaiting review
  root-causes.md                     # RC1–RC8: why the original audit erred (recall fuel)
  checklists/                        # promoted-rule living checklists per family
    security.md  database.md
  regressions/                       # one JSON case per lesson; the FAIL→PASS proof artifacts
    README.md  database/limit-no-order.json
```

### 3.2 The corpus

`.joblet-audit/` is the version-controlled, git-synced knowledge base — the thing that makes this an audit-history-aware reviewer rather than a generic one:

- **`findings.jsonl`** — the catalogue of known Joblet findings, each with `id`, `family`, `pattern`, `severity`, an example `file`, and a `status` of `open`, `fixed`, or `team-fixed` (caught by the team but missed by the original audit — the recall targets). 40 entries at the snapshot.
- **`lessons.jsonl`** — *active* promoted lessons. **Empty in Phase 0** by design: nothing has been promoted yet; all baked knowledge currently lives in the family seed checklists.
- **`quarantine.jsonl`** — proposed lessons (`status:"quarantined"`). At the snapshot it holds two: the `database` `.limit()`-severity knowledge lesson and a `_meta/cynic` *behavior* lesson (the artifact-scope rule) tagged `requires:/456098` and `quarantined-APPLIED-at-build` — a behavior fix the loop only *flagged*, never self-applied.
- **`checklists/<family>.md`** — living checklists holding rules promoted from quarantine via `/35398`; empty in Phase 0.
- **`regressions/<family>/<id>.json`** — the minimal labeled cases (`should_catch` / `should_ignore`) that gate promotion and double as the held-out eval corpus.
- **`root-causes.md`** — RC1–RC8, loaded by Checkers to bias toward recall.
- **`config.json`** — corpus version, the 7 family names, run limits (FAST default, 360s, 6 parallel), the **key hashes** (never the keys), the 15-day provider-token rotation timestamps, the promotion rule, and the knowledge-vs-behavior boundary defaults.

### 3.3 Routing

`orchestrator/routing.json` is the machine-readable wake table. For each family it lists `globs` and `content_signals`; a family wakes on **glob OR content-signal** (content matching is mandatory). Globs are **filename-anywhere** (`**/*ingest*`), not folder-only — validated against the real tree, where root-level `ingest-*.js` scripts and generically-named files would otherwise be missed. The `generalist` family has `globs: ["**/*"]`, `is_fallback: true`, no content signals, no checklist, and always wakes on an unclaimed file, a deletion, or uncertainty. The file also encodes the two **run modes** (`fast` = Checker+Cynic, Researcher on-demand, the default; `deep` = always-run Researcher), the **limits** (360s, 6 parallel), and an `_measured_facts` block carrying the load-test numbers verbatim so families share one source of truth.

### 3.4 The JSON contracts

`orchestrator/json-schemas.md` defines the strict wire format between roles. Shared invariants: `family` is one of the 7 exact names; `severity` is exactly `P0|P1|P2`; ids are `<FAM>-N` (e.g. `security-1`, `db-2`), **stable across the whole run**; `confidence` is a float `0.0–1.0`; null fields are literal JSON `null`.

1. **Checker → Cynic** — `{family, findings:[{id, severity, file:"path:line", line, claim, why, suggested_fix, pass:"checklist|hunt", confidence}]}`. Empty `findings:[]` is valid and correct.
2. **Cynic → Orchestrator (→ Researcher)** — `{family, verdicts:[{id, verdict:"stands|downgrade|refuted|needs-research", severity_if_changed, reasoning}]}`. One verdict per finding; only `needs-research` triggers a Researcher call.
3. **Researcher → Orchestrator** — `{finding_id, ruling:"supports_checker|supports_cynic|partial", final_severity, evidence, source_tier, citation, confidence}`. `final_severity` overrides everything and is never null.
4. **Analyser → quarantine** — `{family, type:"knowledge|regression", proposed, reason, trigger_finding, conflicts_with, regression_ref, requires:"/35398|/456098", status:"quarantined", ts}`.

**Final severity precedence:** Checker `severity` → Cynic `severity_if_changed` → Researcher `final_severity` (later overrides earlier). **Source tag** derives from the deepest role that touched a finding: static pre-pass → `verified`/`[deterministic]`; a Researcher pass → `researched:<tier>`; Checker-only or Cynic-sustained/downgraded without research → `claimed`; otherwise `assumed`.

### 3.5 Install and team sync

1. **Distribute the skill as a Claude Code plugin** so `SKILL.md`, the 5 commands, roles, families, and orchestrator install together and are namespaced — not as loose global commands.
2. **Copy `.joblet-audit/` into the target repo** (`Joblet-Official/joblet1.0`) on the dedicated `joblet-audit-corpus` branch. This is the single source of truth; everyone syncs by pulling it.
3. **Set the key hashes during install** via `keygate.sh set` (run locally by each key holder; the secret never leaves their machine), then commit the updated `config.json`. Read-only provider tokens go in each approver's local env.

`scripts/corpus-sync.sh` is the sync mechanism: `pull` refreshes the active corpus from the canonical branch (read-only); `propose` appends a quarantine suggestion (append-only → no merge conflicts); `promote` (called only by `/35398` after approval + a regression pass) appends a rule to the family checklist, which is then committed to the corpus branch to publish to all installs.

---

## 4. Evidence and limitations

### What has been proven

**The held-out bake-off.** On a 30-case held-out eval set, Joblet-Audit reached **recall 1.00 versus a no-knowledge baseline of 0.85.** The measured edge is **domain knowledge + coverage discipline** — the seed checklists, the corpus of team-caught misses, and the mandatory checklist-floor-then-hunt structure — **not** generic novel-bug cleverness. The open-ended hunt is deliberately aimed at the exact false-negative classes the original audit missed (CSRF, IDOR, client-trusted userId, tokens in localStorage, blog XSS, XXE in XML ingest, `useEffect` without AbortController, BUILD_ID divergence).

**The Cynic regression as a guardrail.** The artifact-scope rule is the single most load-bearing piece of evidence about *what breaks recall*: when a Cynic was allowed to refute in-diff facts by repo-absence, recall fell from **1.00 to 0.57**. That measured collapse is why the rule is hard-coded into the Cynic role and why it lives behind the Source key. It is a strong demonstration that the adversarial second opinion is valuable *only* when correctly scoped to the artifact.

**The load-test calibration.** Thresholds, the ~40 req/s ceiling, the ~60s search bottleneck, and the correct-by-design rate-limiter ruling are all measured (2026-06-11) — replacing the original audit's unverified performance assertions (RC3) with ground truth that families now share.

**Mechanics.** The spike-proven invariants — parallel fan-out, strict JSON contracts, 360s + partial-result safety, Cynic-always-gets-the-artifact, Researcher-on-demand-only, Orchestrator dedup/scope-routing — are validated and treated as non-optional.

### What is still unproven

- **No real in-Claude-Code install yet.** This is a Phase 0 scaffold. Security and Database families are fully seeded; the others are stubbed. The plugin distribution, the corpus branch in the live target repo, and end-to-end install/sync have not been exercised in production. The mechanics are spike-proven, not yet field-proven.
- **Large-diff recall is unmeasured.** The bake-off used 30 small, labeled cases. Whether recall holds on large, multi-file PRs — where retrieval-scoping, the 360s budget, the 6-family parallel cap, and dedup all interact at scale — has not been measured. Timeout pressure and partial-result fallbacks are most likely to bite exactly here.
- **Cynic behavior on noisy diffs is untested.** The artifact-scope rule was validated on clean synthetic diffs. How the Cynic behaves on noisy, real-world diffs — large refactors, mixed renames-plus-logic, deletions — and whether it over-refutes or under-refutes there, is not yet established.
- **No CI tier.** The Researcher cannot run load tests or `EXPLAIN ANALYZE`; every new performance claim is an explicit estimate. Only the one load test is measured ground truth, and it is a point-in-time snapshot of staging — not continuous.
- **The gate is a shared secret, not crypto.** Security rests on key custody and corpus write-access, not on cryptographic strength. That is a deliberate, documented trade-off, appropriate for a small team, but it is not a hardened access-control system.
