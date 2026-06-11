# Family: SEARCH & RELEVANCE

**Lens:** search / autocomplete / suggestion correctness, relevance, and search-path latency. **Roles:** parameterize templates with `{{FAMILY}}=search`. **Token:** `search` → finding ids `search-N`.
**Scope (one line):** search/autocomplete/suggestion correctness + relevance — `ilike '%term%'` ignoring FTS/trigram index, client-side ranking, ranking-destroying post-processing (e.g. `diversifyByCompany` after DB rank), unsanitized `.or()` in suggestions, duplicate endpoints, unjustified ranking-formula changes.

**Canonical table:** `jobs_joveo_partner_v2`. Use `api-handlers/` paths (never stale `api/`).

## Wake rules (glob OR content-signal — over-wake is safe)
| Kind | Values |
|---|---|
| Globs (filename-anywhere) | `**/search/**`, `**/*advanced-search*`, `**/*autocomplete*`, `**/*suggest*`, `**/*query-optimizer*`, `**/*didYouMean*`, `**/*postgrestQuote*`, `**/scripts/**/*search*`, `**/*setup-search*` |
| Content signals | `.ilike(`, `ilike.`, `.textSearch(`, `.or(`, `gin_trgm_ops`, `search_vector`, `tsvector`, `diversify`, `combinedScore`, `runConsolidatedSuggestions`, `fuzzy_search_jobs_companies`, `quotePostgrestOrFilterValue`, `levenshtein` |

## Seed checklist (coverage FLOOR — never skipped; grows only via /35398 + a regression case)

| # | Check | Anchor (current file:line) | Severity | Status now |
|---|---|---|---|---|
| 1 | **`description ILIKE '%term%'` with NO trgm index on canonical table → seq scan.** THE load-test bottleneck. | `api-handlers/search/advanced-search.js:120` builds `description.ilike.${safePattern}` with `likePattern=%term%` (:105). No `description gin_trgm_ops` index on `jobs_joveo_partner_v2` — `scripts/migrations/add_jobs_listing_search_indexes.sql:60-75` covers title/company/location/industry/jobType but OMITS description. | **P0** | OPEN |
| 2 | **pg_trgm GIN coverage gap — the calibrated fix is only PARTIALLY deployable.** | Same migration `:60-75` gives title+company (the 2 of 3 recommended indexes that exist); description missing. Every other trgm SQL (`scripts/setup-search.sql:80`, `setup-search-part1.sql:67`) targets STALE `jobs_joveo_v2`, not canonical. `create_jobs_joveo_partner_v2.sql:104-105` has only a `search_vector` tsvector GIN, which ILIKE cannot use. | **P0** | PARTIAL |
| 3 | **Unsanitized `.or()` built from RAW user query** in the ACTIVE suggestion path (A14/C14 idiom class). | `api-handlers/query-optimizer/consolidated-queries.js:26` `const pattern = \`%${trimmedQuery}%\`` interpolated raw at `:31` into `.or(title.ilike.${pattern},…)` with NO `quotePostgrestOrFilterValue`. Reached via public `GET /api/search?type=suggestions` → `advanced-search.js:259` (`runConsolidatedSuggestions(...)`) → module wired at `advanced-search.js:13` `require('../query-optimizer')` → `index.js:21,38` → `consolidated-queries.js`. Unsanitized `.or()` reachable by user input = **P0** (§5.2); round UP when unsure. | **P0** | OPEN |
| 4 | **Client-side relevance** — first-N rows then JS ranking instead of DB-side top-N (C5). | Confirm DB does the ranking/ordering, not a post-fetch JS sort over an arbitrary page. | P1 | — |
| 5 | **Ranking-destroying post-processing** — `diversifyByCompany` applied AFTER DB rank, RANDOMIZING relevance order (C12). *(Cynic-caught originally; would have wasted the FTS migration.)* | `advanced-search.js:198` sorts by `matchCount`→`combinedScore`, then `:207` calls `diversifyByCompany(jobs)`. `_lib/diversifyByCompany.js:23-26` runs a `Math.random()` Fisher-Yates shuffle of the company groups AFTER the relevance sort, genuinely randomizing cross-company relevance order — confirmed in current source, not hypothetical. | **P1** | OPEN |
| 6 | **`.limit()` with no `ORDER BY` on a large table → P1** (suggestion quality depends on heap order; non-deterministic). | `consolidated-queries.js:32` `.limit(200)` on the title/company/industry ILIKE `.or()` with no `.order()`. | **P1** | OPEN |
| 7 | **`select('*')` in hot search read path** (E6 idiom — over-fetch + compounds the seq-scan cost). | `advanced-search.js:117` `.select('*')` on canonical table with `.range(0, fetchLimit-1)`, `fetchLimit=min(limit*5,100)` (:112) — pulls description/search_vector/ml scores for ≤100 rows then maps a fixed subset (:161-194). | **P2** | OPEN |
| 8 | **Autocomplete p95 ~2.5s breaches <100ms budget** — substring branch + serial fuzzy fallback. | `job-autocomplete.js:65` uses `%term%` for queries >3 chars (≤3 get prefix `term%`, which existing title/company trgm serves). When `scored.length<=3`, a SERIAL RPC round-trip `fuzzy_search_jobs_companies` (:135-140) + up to 4 parallel verification lookups (:152-163). | **P2** | OPEN |
| 9 | **Duplicate / divergent suggestion endpoints** doing the same work inconsistently (C13). | The SAFE copy `api-handlers/query-optimizer.js:26` (uses `pgrstQuote`) is NOT wired up; Node resolves `require('../query-optimizer')` to the DIRECTORY `index.js`, exporting the UNSANITIZED `consolidated-queries.js`. Fix must land in `consolidated-queries.js`, not the dead sibling. | P2 | OPEN |
| 10 | **Relevance regression** — change to ranking formula (RRF weights, vector↔FTS blend, `combinedScore` weights) without justification or a test. | `advanced-search.js:159` weights title*500 / industry*300 / desc*100 / company*50. | P2 (P1 if a tested ranking formula is replaced) | — |

## OPEN-ENDED HUNT (recall-graded — the checklist is a floor, not a cage)
Beyond the table, hunt for: a NEW search path reintroducing raw-`.or()` interpolation; a second `select('*')` creeping into autocomplete/suggestions (currently only `advanced-search.js:117` — `job-autocomplete.js:71` and `consolidated-queries.js:30` select only needed columns); a `.limit()` without `.order()` on any new suggestion query; ranking changed silently; an RPC relied on without a defined function (graceful-fallback robustness, not P-level — see below); FTS/`search_vector` wired in but bypassed by an ILIKE branch.

## Verified-FIXED (record to PREVENT false positives — do NOT re-flag)
| Item | Why it's fixed |
|---|---|
| A14/C3/C14 unsanitized `.or()` in PRIMARY autocomplete | `job-autocomplete.js:66` `quotePostgrestOrFilterValue(likePattern)` then quoted `pat` at :72. `advanced-search.js:108,118-121` routes through the same helper (`_lib/postgrestQuote.js:12-18`). The GAP is the consolidated sibling (#3/#9), NOT these. |
| C5/C12 did-you-mean / relevance ranking | `_lib/didYouMean.js` — bounded Levenshtein (:30-51), edit-distance≤2 gate, length pre-gate (:102), `titleCap=min(maxTitles,500)` (:82), request-local vocab from already-returned titles (no extra DB hit). Stable `matchCount`→`combinedScore` sort. FIXED, no regression. |
| `is_active` schema probe | `_lib/jobsTableSchema.js:46-57` bakes `KNOWN_TABLE_DEFAULTS`; `resolveIsActiveColumnSupport` (:136-169) returns cached/default for known tables, in-flight promises deduped. The `Promise.all([resolveIsActiveColumnSupport(...)])` in `job-autocomplete.js:58-61` adds NO per-request round-trip. Do NOT flag as latency overhead. |
| `fuzzy_search_jobs_companies` RPC undefined | `job-autocomplete.js:136` calls an RPC not defined in any repo SQL (verified absent). Relies on graceful error fallback → robustness NOTE only, NOT a P-level finding. |

## LATENCY BUDGETS — MEASURED (load test, staging 2026-06-11)
| Path | Budget | Now | Tag |
|---|---|---|---|
| search p95 | < 300ms | **~60s** (ILIKE `%term%` seq scan → hits Vercel 60s function timeout) | **MEASURED — THE bottleneck (C15/A20/C18)** |
| autocomplete p95 | < 100ms | **~2.5s** (functional but slow) | **MEASURED** |
| Calibrated fix | — | 3 `pg_trgm` GIN on `jobs_joveo_partner_v2` (title, **description**, company) → search p95 60s→**<1s** | MEASURED recommendation; description index is the missing piece |

Calibrated ground truth (treat as fact): DB sustains ~40 req/s before search latency climbs; active-user ceiling 200–400 now → 1,500–2,500 post-index; error rate under stress 1.6% (mostly timeouts). **Do NOT flag** the 60 req/min limiter, the 60s function timeout, the Supabase tier, or the in-memory autocomplete cache (`job-autocomplete.js:10-25`, 10-min TTL / 200 entries) as defects — correct by design per load-test calibration.

## Cynic tuning (artifact-scope rule applies)
Judge each finding against the PROVIDED diff/snippet — never refute an in-diff fact by repo-absence. Reading the repo may only ADD nuance (reachability, an index that already exists), never erase an in-diff defect. Legitimate refutes: the searched column IS trgm/FTS-indexed on `jobs_joveo_partner_v2`; the diversify/shuffle runs BEFORE ranking; the endpoint is intentionally distinct; the `.or()` value already passes through `quotePostgrestOrFilterValue`/`pgrstQuote`. Distinguish *correctness* (wrong results) from *latency* (now MEASURED, no longer deferred). Mark `needs-research` only when an external/repo fact (index existence, PostgREST/Postgres semantics) decides it.

## Researcher tuning (fires only on `needs-research` / novelty)
Tiers: our-code → canonical-docs (PostgREST `.or()`/`textSearch`, Postgres GIN/`pg_trgm`/`pgvector`, tsvector vs ILIKE, CLRS for RRF) → current-practice → frontier. Every claim source-tagged. The load-test numbers above are **MEASURED** and may be cited as such; any NEW perf claim the Researcher invents is `"estimate — verify in staging"` (no CI / no EXPLAIN on prod).
