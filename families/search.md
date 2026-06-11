# Family: SEARCH & RELEVANCE

**Lens:** search / autocomplete / suggestion correctness + relevance. **Roles:** substitute `{{FAMILY}}=search`.
**Glob triggers:** `**/search/**`, `**/*autocomplete*`, `**/*suggest*`, `**/job-autocomplete*`, `api-handlers/query-optimizer/**`
**Content signals:** `.textSearch(`, `.ilike(`, `.or(`, `diversify`, `rank`, `rrf`, `pgvector`, `runConsolidatedSuggestions`

## Seed checklist (coverage floor — grows via /35398)
1. **`ilike` on a column that should use the FTS / trigram index** (C15) — substring `%term%` on `description`/`title` ignores the index → seq scan. Prefer the hybrid FTS path.
2. **Client-side relevance** — taking first-N rows then ranking in JS instead of DB-side top-N ranking (C5).
3. **Ranking-destroying post-processing** — a shuffle/diversify step (e.g. `diversifyByCompany`) applied *after* DB ranking, discarding relevance order (C12). *(Cynic-caught originally; would have wasted the FTS migration.)*
4. **Unsanitized `.or()` in suggestions** (C3/C14) — overlaps Security; flag and let the Orchestrator route. Fix: `quotePostgrestOrFilterValue`.
5. **Duplicate / overlapping suggestion endpoints** doing the same work inconsistently (C13).
6. **Relevance regression** — a change that alters the ranking formula (RRF weights, vector vs FTS blend) without a justification or test.

## Cynic tuning
Refute on: the column is actually FTS-indexed; the shuffle is before ranking; the endpoint is intentionally distinct. Distinguish *correctness* (wrong results) from *latency* (Phase 5).

## Researcher tuning
Tier-2 focus: PostgREST `.or()`/`textSearch` semantics, Postgres GIN/trigram/`pgvector` index behavior, Reciprocal-Rank-Fusion correctness. **Latency/perf claims tagged "estimate — verify in staging"** (deferred to Phase 5).

_Phase-5 note: search-latency thresholds (autocomplete <100ms, search <300ms) are uncalibrated until the load test lands._
