# Family: DATABASE & DATA INTEGRITY

**Lens:** correctness of DB reads/writes, idempotency, data safety. **Roles:** substitute `{{FAMILY}}=database`.

**Glob triggers:** `**/ingest*/**`, `**/sync*/**`, `**/*.sql`, `api-handlers/**`, `**/_lib/**`, `**/bulk-operations*`
**Content signals:** `.from(`, `.insert(`, `.update(`, `.upsert(`, `.delete(`, `count: 'exact'`, `.limit(`

## Seed checklist (coverage floor — grows via /35398)
1. Write to the wrong / legacy table (not the canonical `jobs_joveo_partner_v2`) (B5/M2).
2. Non-idempotent insert / random-id fallback for records lacking a stable key (B2/B17).
3. Mass deactivation / destructive write with no staleness predicate or kill-switch (B18/D15).
4. `.limit()` query with NO `ORDER BY` → arbitrary/unstable rows, no progress fairness (D17).
5. Fire-and-forget DB write — missing `await` on an async insert/update (supabase-js thenables only run when awaited).
6. `count: 'exact'` on a large table on a hot path (A15).
7. Unchecked `{data, error}` destructure → null deref / swallowed error.
8. SELECT-then-INSERT race instead of an upsert on a unique constraint.

## Cynic tuning
Refute on: the write is actually awaited via return; the table is correct; severity over-rated. Watch for findings that are really security (kick to security family).

## Researcher tuning
Tier-2 focus: PostgREST ordering/pagination semantics, supabase-js thenable execution model, Postgres index/`EXPLAIN` (tag perf as estimate — verify in staging).
