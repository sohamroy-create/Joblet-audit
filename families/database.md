# Family: DATABASE & DATA INTEGRITY

**Lens:** correctness, idempotency, and safety of DB reads & writes against Postgres/PostgREST (Supabase). **Role binding:** `{{FAMILY}}=database`, `<FAM>=db`. **Canonical jobs table = `jobs_joveo_partner_v2`** (env `JOBS_TABLE_NAME`). Handlers live under `api-handlers/` (NOT `api/`).

**Scope vs siblings:** raw `.or()`/`.filter()` injection and service-role exposure are SECURITY's call — flag DB *correctness* here, kick injection framing to security (Cynic refutes with `out of scope: security`). Self-heal worker *operational* safety (probe fail-open, kill-switch, backpressure) is CRON-RELIABILITY; the DB *query-shape* defects inside those workers (unordered `.limit()`) are shared — Orchestrator dedups by `file:line`.

## Routing (mirror of orchestrator/routing.json `families.database` — filename-anywhere globs)
| | values |
|---|---|
| **globs** | `**/*ingest*`, `**/*sync*`, `**/*.sql`, `**/api-handlers/**`, `**/_lib/**`, `**/*bulk*`, `**/*Service.ts`, `**/*migrate*` |
| **content_signals** | `.from(`, `.insert(`, `.update(`, `.upsert(`, `.delete(`, `count: 'exact'`, `count:'exact'`, `.limit(`, `jobs_joveo_partner_v2`, `JOBS_TABLE_NAME`, `randomUUID`, `random-id` |

Globs are filename-anywhere (root-level `ingest-*.js` / `create_*.sql` exist and were missed by folder-only globs — validated 2026-06-11). Path-glob OR content-signal wakes the family; over-waking is safe.

## Seed checklist (coverage FLOOR — do this pass, then open-ended hunt; floor not cage)
| # | Check | Sev | Anchor |
|---|---|---|---|
| D-1 | Write to wrong/legacy table, not canonical `jobs_joveo_partner_v2` | P0/P1 | B5/M2 |
| D-2 | Non-idempotent insert: random-id fallback for key-less records → duplicate rows on re-ingest | P2 | B2/B17 |
| D-3 | Mass deactivation / destructive write with no staleness predicate AND no kill-switch | P0/P1 | B18/D15 |
| D-4 | `.limit()` with **NO `ORDER BY`/`order=` on a large table → P1** (non-deterministic slice, fairness loss) | **P1** | D17 |
| D-5 | Fire-and-forget write: missing `await` on a supabase-js thenable (only runs when awaited/`.then`) or raw `fetch` POST | P1 | — |
| D-6 | `count:'exact'` on a hot path WITHOUT `head:true` (double-fetches rows) | P2 | A15 |
| D-7 | Unchecked `{ data, error }` destructure → null deref / swallowed write failure | P2 | D16 |
| D-8 | SELECT-then-INSERT race instead of `upsert` on a unique constraint | P1 | — |
| D-9 | `select('*')` over-fetch on server-side service-role/admin read (PII/`password_hash` over the wire) | P2/P1 | E6 |
| D-10 | Leading-wildcard `ilike '%term%'` on a large table with no trgm/FTS index applied → seq scan | P0 | C15/A20/C18 |

Severity default: **pessimistic when unsure — round UP** (Checker historically under-rated). Static pre-pass already emits `S-SELECT-STAR` for `src/lib/*Service.ts` `select('*')` as `[deterministic]`; do NOT re-derive those — take them as CONTEXT and extend only with reachability/PII nuance.

## OPEN findings in current repo (information floor — confirm if touched, do not re-litigate as new)
| id | file:line | claim | sev | status |
|---|---|---|---|---|
| db-1 | `create_jobs_joveo_partner_v2.sql:104-105` (ships only btree + `search_vector` FTS GIN, no trgm) vs live `api-handlers/_lib/jobListingQueryFilters.js:299-304` + `jobs.js:980` `runMainListQuery({forceIlike:true})` + `job-autocomplete.js:65` | `ilike '%term%'` substring filters on canonical table; the 5 `idx_jjpv2_*_trgm` fix EXISTS as a migration (`scripts/migrations/add_jobs_listing_search_indexes.sql:60-75`) but is **UNAPPLIED in prod** → seq scan → search p95 ~60s (Vercel 60s timeout). THE bottleneck. **Operational gap, not a code gap.** | P0 | OPEN |
| db-2 | `scripts/self-healing/workers/applyLinkChecker.js:106` `buildCandidateQuery` | `&limit=${poolSize}` with **NO `order=`** clause on the candidate pool → PostgREST returns an arbitrary slice each run; a subset of stale jobs is never revisited | **P1** | OPEN (D17) |
| db-3 | `api-handlers/ingest-joveo-partner-v2.js:160` `transformJob` | ref-less jobs get `` `${feedConfig.id}-${Date.now()}-${Math.random()...}` `` → fresh id every run; `upsertBatch` uses `on_conflict=id` + `Prefer: resolution=merge-duplicates` (:87,:99) so it can never dedup them → new row each ingest cycle. Ref'd jobs ARE idempotent (B2/B17 collisions gone) | P2 | PARTIAL |
| db-4 | `src/lib/supabase.ts:236` `getUserFromSupabase` `select('*')` via `supabaseAdmin` (+ 10 more occurrences across `adminService/advertiserService/applicantService/recruiterService`) | over-fetches every column incl. PII/`password_hash` on hot service-role reads | P2 | OPEN (E6) |

**Searched-but-CLEAN (do not re-flag):** company-logo enrichment batches via `.in('company_id', ids)` (`enrichJobsWithCompanyLogos.js:202-205,262-265`) — correct idiom, NOT N+1. `/api/jobs` listing pairs `.range()` with `.order()` (`jobs.js:787,810-825`) — ordered; the unordered-`.limit()` defect is ONLY the self-heal pool (db-2). Ingest `on_conflict=id` upsert is correct idempotency for ref'd jobs. Hybrid search uses RPCs (`hybridSearch.js:81-96`), not raw interpolation.

**FIXED (regression-guard only — flag a REGRESSION if a diff reverts these):**
- A15 count: `jobs.js:66,147` use `.select('id', { count:'exact', head:true })` (+ estimated fallback :83,:175) — no double-fetch. Reintroducing `count:'exact'` without `head:true` ⇒ db-6.
- A14/C3/C14 `.or()` sanitize: `job-autocomplete.js:66-72` routes the pattern through `quotePostgrestOrFilterValue` (`api-handlers/_lib/postgrestQuote.js`); `forceIlike` path (`jobListingQueryFilters.js:300,303`) also quotes. Injection class closed on these paths. (Note: `supabase.ts:187` raw `.or()` on `supabaseAdmin` is STILL OPEN but is a SECURITY finding — kick it there.)

## Severity rules (prescriptive)
- **`.limit()` with no `ORDER BY` on a large table = P1**, not P2 (regression `db-reg-1`, `claim_contains:"ORDER BY"`, `min_severity:P1`). Applies here AND in cron-reliability.
- Wrong/legacy table write or unindexed `'%term%'` scan on a hot path that breaches the search budget = **P0** (data-correctness / outage class).
- Random-id non-idempotency that only duplicates rows (no data loss) = **P2** (mitigated for ref'd jobs).
- Mass deactivation: P0 if no kill-switch AND no staleness predicate; P1 if one guard present. (Kill-switch `SELF_HEAL_MISSING_DISABLE_DEACTIVATION` is OFF in prod env.)

## Cynic tuning (artifact-scope rule)
Judge each finding against the **provided diff/snippet**, never refute an in-diff defect by repo-absence — reading the repo may only ADD nuance (an index already applied, a write actually awaited, the table correct). Refute on: write IS awaited (return value awaited / `await`ed thenable); table is canonical; `head:true` present with the count; `.limit()` is on a small/bounded set or IS paired with `order=`; the finding is really injection/exposure → `out of scope: security`. The unapplied-index finding (db-1) is an OPERATIONAL gap — do not refute it just because the migration file exists in the repo; the load test (p95 ~60s) is the deciding fact.

## Researcher tuning (fires only on `needs-research` / novelty)
Tier-2 anchors: PostgREST ordering/pagination & `Prefer: resolution=merge-duplicates` semantics; supabase-js thenable execution model (queries run only when awaited/`.then`); Postgres `pg_trgm` GIN vs btree vs `tsvector` FTS, `EXPLAIN`. No CI / no prod `EXPLAIN ANALYZE` ⇒ any NEW perf claim is tagged `"estimate — verify in staging"`. **EXCEPTION (cite as MEASURED, load test 2026-06-11):** search p95 ~60s seq-scan → <1s with the `pg_trgm` GIN indexes the migration (`scripts/migrations/add_jobs_listing_search_indexes.sql:60-75`) actually ships on `jobs_joveo_partner_v2` — 5 `idx_jjpv2_*_trgm` indexes on title/company/location/industry/jobType (NO `description` trgm index, despite the spec/load-test recommendation wording of "title/description/company" — the on-disk migration is the ground truth); autocomplete p95 ~2.5s breaches the <100ms budget; DB sustains ~40 req/s before search latency climbs. Latency budgets: search p95 <300ms (MEASURED breach), autocomplete p95 <100ms (MEASURED breach), page LCP <1.5s (ESTIMATED). Do NOT flag the 60/min rate limiter, the 60s function timeout, or the Supabase tier — correct by design.
