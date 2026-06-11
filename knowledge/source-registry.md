# Researcher knowledge source registry

How the Researcher grounds a ruling. The Researcher fires ONLY on a Cynic `needs-research` verdict OR diff novelty (spec §1 Step 4, §3.3 on-demand-only). Every claim it emits carries a `source_tier` + `citation`; an untagged claim is an assumption, not evidence (spec §2.3). Output one ruling object per finding per the §2.3 contract.

## Tier model (the 4 `source_tier` values — frozen, used verbatim in JSON)
| Tier | Value | What it is | Use for |
|---|---|---|---|
| 1 | `our-code` | repo@HEAD (clone at `/tmp/joblet-src`), the diff, DB schema, `.joblet-audit/findings.jsonl` | Reachability — is this path hit with attacker/real input? Does the file/table/env actually exist? |
| 2 | `canonical-docs` | CS/DSA texts (CLRS) + official docs for our stack | The authoritative "how does X behave" tie-break |
| 3 | `current-practice` | StackOverflow, GitHub issues, changelogs, CVEs/advisories | Known bugs, version-specific gotchas, real-world failure modes |
| 4 | `frontier` | latest advances + known pitfalls for genuinely novel tech | Only when the diff introduces tech the family's known set does not name (novelty) |

Prefer the shallowest tier that settles the finding. `our-code` reachability often resolves a `needs-research` without any external fetch.

## Family → preferred sources (tiers 2–4)
The 7 families per spec §4. `generalist` is a pure recall fallback with no static checklist; when it raises a finding that needs research, route by the finding's actual subject to the matching row below.

| Family | Canonical-docs (tier 2) | Current-practice (tier 3) |
|---|---|---|
| security | PostgREST filter/`.or()` grammar; Firebase Auth (`email_verified`, account-linking/uniqueness); Supabase RLS + `supabaseAdmin` service-role semantics; OWASP (IDOR/CSRF/XSS/XXE) | CVEs for `@supabase/*`, `firebase`; OWASP cheat sheets |
| database | PostgREST ordering/pagination; supabase-js thenable execution model; Postgres index/`EXPLAIN`; idempotency/upsert semantics; CLRS (complexity) | supabase-js issues on un-awaited writes, upsert/`onConflict` races, `count:'exact'` cost |
| search | Postgres FTS / GIN / `pg_trgm`; `pgvector`; Reciprocal-Rank-Fusion; `ILIKE '%term%'` → seq-scan cost; FastAPI (`services/embed-service`) request/response model where a finding touches the embed surface | `pg_trgm` GIN write-ups; ranking-pipeline pitfalls (post-rank reordering) |
| frontend-seo-aeo | Next.js 14 App Router metadata/canonical/SSR; React effect cleanup (`AbortController`); CSP spec; schema.org `JobPosting` | Google Search Central; web.dev CSP. NOTE: SEO is deterministic (static pre-pass, spec §3.4) — agent loop owns frontend logic + AEO only |
| middleware-scalability | Vercel Fluid/Edge isolate model + 60s function timeout; Supabase/Supavisor pooling; `Cache-Control` semantics; backpressure patterns; KafkaJS consumer/producer + backpressure semantics where middleware touches Kafka | Vercel docs/changelog; per-isolate in-memory cache/limiter behavior |
| cron-reliability | Vercel Cron + `CRON_SECRET` model; idempotency/kill-switch patterns; HTTP status semantics (health-probe correctness); circuit-breaker; KafkaJS consumer/offset/commit semantics for self-healing workers and schedulers that touch Kafka | Vercel cron issues; self-healing-worker failure modes |

## Novelty mode — when to escalate to tier 4 `frontier`
Fire novelty research when the diff introduces a dependency / framework primitive / technique **not present** in the family's known set (a new import, a new API, a pattern the checklist does not name) — this is the second of the only two Researcher triggers (spec §1 Step 4). Emit a short "state-of-the-art + pitfalls" brief BEFORE the family finalizes, tagged `frontier` with citations. Counters reasoning against stale assumptions. Over-research on true novelty is acceptable; silently treating new tech as familiar is not.

## Citation + caching discipline
- **Citation format:** `tier · source-name · (section / URL / CVE-id)`. Put the deciding facts in `evidence`; put the source string in `citation`. An untagged claim is an assumption (spec §2.3).
- **Cache** common tie-break lookups (Firebase `email_verified` behavior, supabase-js await semantics, PostgREST `.or()` parsing, `pg_trgm` index behavior) in `knowledge/cache.jsonl`, keyed by question-hash, so repeat rulings don't re-research. Each entry carries a `checked_on` date; re-validate stale entries before reusing them.
- **Confidence** is mandatory (0.0–1.0). Per spec §2.3, `partial` is a semantic ruling — return it when the evidence partially supports each side — not a confidence-score gate; a genuinely-decided finding stays `supports_checker`/`supports_cynic` even at low confidence.
- Cynic artifact-scope still holds upstream: a `needs-research` exists because the deciding factor is an external/repo fact, never an in-diff fact the Cynic could have read directly (spec §2.2, §5.2).

## perf = estimate rule (hard line)
The skill has NO CI: the Researcher CANNOT run load tests or `EXPLAIN ANALYZE` against prod (spec §2.3, §5.3). Therefore:
- Any NEW performance claim the Researcher makes MUST be tagged `"estimate — verify in staging"` inside `evidence`, and never asserted as measured.
- **The ONLY exception** is the staging load test (2026-06-11), which IS measured and may be cited as such:

| Measured fact (cite as MEASURED, source `our-code` / load test) | Number |
|---|---|
| DB sustains before search latency climbs | ~40 req/s |
| Search p95 under concentrated load (`ILIKE '%term%'` → seq scan → Vercel 60s timeout) — THE bottleneck (confirms C15/A20/C18) | ~60s |
| Autocomplete p95 (functional but slow; budget <100ms) | ~2.5s |
| Recommended fix: 3 `pg_trgm` GIN indexes on `jobs_joveo_partner_v2` (title, description, company) → search p95 | 60s → <1s |
| Concurrent ACTIVE-user ceiling now → post-index | 200–400 → 1,500–2,500 |
| Casual browsing ceiling now → post-index | 2,000+ → 5,000+ |
| Error rate under stress (mostly timeouts) | 1.6% |

- **Leave alone (correct by design — do NOT flag, do NOT "fix"):** the 60 req/min/IP API limit (120/min pages, per-edge-isolate, in-memory; 87% 429 under a single-source flood is intended bot defense), the 60s function timeout, and the Supabase tier (spec §5.3). The defect class is MISSING / over-wide limits, not the limiter itself.
- Latency budgets to cite (the budget is the TARGET; the MEASURED current number is in the table above): autocomplete p95 < 100ms (budget target; MEASURED ~2.5s breaches it), search p95 < 300ms (budget target; MEASURED ~60s breaches it), page LCP < 1.5s (target; ESTIMATED unless a measured number is cited).
