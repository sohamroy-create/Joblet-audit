# Family: MIDDLEWARE & SCALABILITY  (CALIBRATED — load test 2026-06-11)

**Lens:** middleware, caching, connection pooling, frontend↔backend scalability. Substitute `{{FAMILY}}=middleware-scalability`.
**Glob triggers (filename-anywhere; mirror `orchestrator/routing.json`):** `**/middleware.ts`, `**/middleware/**`, `**/*rate-limit*`, `**/vercel.json`, `**/*db*`, `**/*pool*`, `**/*cache*`, `**/*supavisor*`
**Content signals (mirror `orchestrator/routing.json`):** `new Map(`, `Cache-Control`, `rateLimit`, `rate-limit`, `pool`, `Supavisor`, `maxDuration`, `revalidate`

Thresholds below are **MEASURED (load test 2026-06-11)** unless tagged `ESTIMATED`. Cite `file:line` against current HEAD (`acaf775`). Use `api-handlers/` (not `api/`) and `jobs_joveo_partner_v2`.

---

## CALIBRATION GROUND TRUTH (treat as fact; do NOT re-derive or re-flag)

| Fact | Value | Tag |
|---|---|---|
| DB throughput ceiling | **~40 req/s** before search latency climbs | MEASURED |
| search p95 (current) | ~60s — ILIKE `'%term%'` → seq scan → hits Vercel 60s fn timeout | MEASURED (SEARCH/DB family) |
| search p95 target | < 300ms | MEASURED budget |
| autocomplete p95 (current) | ~2.5s (functional, slow) | MEASURED (SEARCH family) |
| autocomplete p95 target | < 100ms | MEASURED budget |
| page LCP target | < 1.5s | ESTIMATED |
| THE fix (dependency) | 3 `pg_trgm` GIN indexes on `jobs_joveo_partner_v2` (title, description, company) → search p95 60s→<1s | MEASURED recommendation |
| active-user ceiling | 200–400 now → 1,500–2,500 post-index | MEASURED |
| casual-browse ceiling | 2,000+ now → 5,000+ post-index | MEASURED |
| error rate under stress | 1.6% (mostly timeouts) | MEASURED |

**The trigram-index dependency:** the ~40 req/s ceiling is set by the search seq-scan, NOT by middleware. Until the 3 `pg_trgm` GIN indexes land, every scalability number above is gated by the SEARCH/DATABASE bottleneck (C15/A20/C18). This family must NOT re-claim that bottleneck — note it as the upstream dependency only.

---

## NOT A DEFECT — DO NOT FLAG (calibration directive)

The per-edge-isolate, in-memory rate limiter is **CORRECT BY DESIGN.** Refute any finding that calls these a bug.

| Item | Evidence | Why it is correct |
|---|---|---|
| Per-isolate `Map` rate limiter (NOT globally aggregated) | `lib/rate-limit.ts:15` `const buckets = new Map<string,TokenBucket>()`; header lines 4-8 document the trade-off + Upstash-Redis upgrade path; wired `middleware.ts:201` `rateLimit(key,limit,WINDOW_MS)`, key=`api\|page:<ip>` (`middleware.ts:199`) | 87% 429 under single-source flood is **intended bot defense**, not a bug. Cross-location aggregation is a documented, optional hardening, not a defect. |
| 60/min API + 120/min page limit | `middleware.ts:22-23`, used `middleware.ts:198` | Calibrated correct. **Leave the 60/min limit ALONE.** |
| 60s Vercel function timeout | platform default | Leave ALONE per calibration. |
| Supabase tier | — | Leave ALONE per calibration. |
| Lazy bucket eviction (≤ once/60s, inline) | `lib/rate-limit.ts:20-26` gated by `CLEANUP_INTERVAL_MS`, runs inside `rateLimit()` line 45 | Bounded by distinct IPs/min; self-correcting on traffic; no `setInterval` leak on Edge. INFO only. |
| Per-request CSP nonce + privacy cookie in Edge hot path | `middleware.ts:272-283` `buildResponse()` → `generateCspNonce()` (`middleware.ts:8-14`, 16-byte `crypto.getRandomValues`+base64) + `buildContentSecurityPolicy()` (`src/lib/csp.ts:55`) | Unavoidable cost of nonce+strict-dynamic CSP (E3-FIXED). No cheaper correct alternative. INFO only. |
| Env-overridable limits (`API_RATE_LIMIT`/`PAGE_RATE_LIMIT`) | `middleware.ts:22-23` `Number(process.env.API_RATE_LIMIT)\|\|60` / `PAGE_RATE_LIMIT\|\|120`; staging load-test escape hatch (comment 16-21); **NOT set in prod** per Vercel env read 2026-06-11 → safe defaults (60/120) apply | Dormant in prod: env vars unset → calibrated safe defaults in force. INFO only — NOT an OPEN checklist finding. Becomes a real defect class (OVER-WIDE limit) ONLY if a diff sets these over-wide in a prod env; flag that as MS-style P1+ if seen. |

**The DEFECT class for this family is MISSING or OVER-WIDE limits — not the existence of a limit.**

---

## Checklist pass (coverage FLOOR — never skipped)

| # | Check | Where | Severity | Status |
|---|---|---|---|---|
| MS-1 | DB-heavy cron routes run on DEFAULT fn timeout — no `functions{}` `maxDuration` override, while regional siblings get 60s + pinned region | `vercel.json` crons lines 44-113 vs `functions{}` lines 12-43; un-overridden: `/api/selfheal/apply-link-checker` (generic, 57-60), `service-probe`, `missing-from-feed`, `expired-jobs`, `company-logo-checker`, `sync-jobs`, 3×`seo/*`, `collect-metrics`; contrast regional apply-link-checker-us/eu/apac get `maxDuration:60` (lines 25-36) | **P2** | OPEN — dedup w/ cron-reliability |
| MS-2 | Middleware matcher excludes `.xml/.json/.txt` → force-dynamic SEO routes bypass the limiter (and CSP/privacy path) | `middleware.ts:292` negative-lookahead excludes `...\.(?:...\|json\|xml\|...\|txt\|map)$`; force-dynamic routes `app/sitemap.xml/route.ts`, `app/sitemap-blog.xml/route.ts`, `app/sitemap-jobs/[shard]/route.ts` | **P2** | PARTIAL — MITIGATED by CDN cache (see below) |
| MS-3 | Legacy Express limiter (30/min) + in-memory response cache diverges from prod Edge limiter; dead code on Vercel | `middleware/rateLimiter.js:106-143` (`max:30`/1min), imported only by `server.js:44` + `server/index.js`; prod uses `next start` (`package.json:27`) + `middleware.ts` (60/120) | **P2** | OPEN — doc/maint hazard; real defect for non-Vercel deploy |
| MS-5 | Cron+ingest+live-traffic pool contention vs the ~40 req/s DB ceiling | `vercel.json` crons (lines 44-113) fire DB-heavy workers; ingest (`ingest-joveo-partner-v2.js`) + live search share the Supabase pool; ceiling is ~40 req/s (MEASURED) | **P2** | HUNT — verify Supavisor/pooler config; estimate, verify in staging |
| MS-6 | Backpressure on Edge-bypassing or unthrottled paths | any matched path that escapes the 60/120 limiter (MS-2) or a worker without a concurrency cap | **P2** | HUNT |
| MS-7 | `Cache-Control` correctness on SSR / dynamic routes | each SEO route MUST set `s-maxage`+`stale-while-revalidate` (see MITIGATION) | **P2** | check on change |
| MS-8 | SSR not reflecting query params (cache-key vs param mismatch) | A3 — verify cache-busting query variants on force-dynamic routes don't poison/bypass CDN | **P2** | HUNT |
| MS-9 | Request without timeout / no request-size limit | 29.6.3 / 29.4.3 — fetches in Edge/handlers lacking abort/timeout or body-size cap | **P2** | HUNT |

**MS-2 MITIGATION (why P2, not higher):** each SEO route sets CDN cache headers — `app/sitemap.xml/route.ts:74` `public, s-maxage=1800, stale-while-revalidate=86400`; `app/sitemap-jobs/[shard]/route.ts:97` `s-maxage=3600/swr=86400`; `app/sitemap-blog.xml/route.ts:49` `s-maxage=300`. Vercel CDN absorbs repeat hits; origin shielded. Residual risk only on cache-busting query variants (links to MS-8).

---

## Open-ended HUNT pass (recall-graded; checklist is a FLOOR, not a cage)

Hunt for the false-negative classes the audit historically missed. Patterns to probe:
- **Missing limit / over-wide limit** anywhere a new route or worker is added (the real defect class). New `api-handlers/*` route with no rate-limit path? New cron with no `maxDuration`?
- **New `functions{}` entries vs new crons** — does every DB-heavy cron get a matching `maxDuration`? (MS-1 generalizes.)
- **Pool contention**: new cron/worker that opens DB connections concurrently with live traffic against the ~40 req/s ceiling (MS-5).
- **`Cache-Control` regressions**: a force-dynamic route losing `s-maxage`/`stale-while-revalidate` re-exposes origin (MS-2 un-mitigates).
- **Matcher changes** in `middleware.ts:292` that widen the bypass set, or remove the limiter from a hot path.
- **Request hygiene**: `fetch` without `AbortController`/timeout (29.6.3); handler accepting a body with no size cap (29.4.3).
- **Edge hot-path cost** added to `buildResponse()` beyond the unavoidable CSP/cookie work.

---

## NOT CLAIMED HERE (hand off; do NOT double-count)

| Item | Belongs to | Note |
|---|---|---|
| ILIKE `'%term%'` seq scan / autocomplete 2.5s / search 60s | SEARCH + DATABASE | THE bottleneck (C15/A20/C18). This family only cites it as the upstream `pg_trgm` dependency. |
| E4 CSP `connect-src` wildcard `https:`/`wss:` | SECURITY (static pre-pass S-CSP-CONNECT) | `src/lib/csp.ts`, STILL OPEN. |
| 79 force-dynamic API routes / `select('*')` Service files | DATABASE / SECURITY E6 | static pre-pass S-SELECT-STAR. |
| `isApiKeyValid` uses `===` not `timingSafeEqual` | SECURITY-low | `lib/api-key.ts:17`; gateway key is `NEXT_PUBLIC_` (non-secret) → timing-oracle is low. Hand-off note only. |
| MS-1 cron `maxDuration` straddles cron-reliability | cron-reliability | flagged here because it lives in `vercel.json` (this file set); Orchestrator dedups. |

---

## Severity guidance (this family)

- MISSING or OVER-WIDE limit reachable under load = **P1+** (round up when blast radius ambiguous).
- Config asymmetry that can silently truncate large batches (un-overridden `maxDuration`) = **P2.**
- CDN-mitigated bypass = **P2** (mitigation is real but residual risk exists; P2 is the lowest valid tier — never P3).
- Divergent dead config (Express limiter) = **P2** doc/maint hazard (also P2 if a non-Vercel deploy target is in scope).
- Per-isolate limiter, 60/min limit, 60s timeout, Supabase tier, lazy eviction, per-request CSP cost, dormant env-overridable limits = **NOT defects** (refute / INFO only).
- Severity values are exactly **P0|P1|P2** (Architecture Spec 2.1/5.1). There is NO P3: the lowest valid tier is P2 (lower-impact correctness or hygiene). A genuinely informational/dormant item belongs in the NOT A DEFECT/INFO section, not in the checklist.
- Any NEW perf claim from the Researcher = `"estimate — verify in staging"`; the load-test numbers above are the MEASURED exception.

---

## Cynic tuning (artifact-scope rule)

Judge each finding against the **PROVIDED diff/snippet**, never refute an in-diff fact by repo-absence (a buggy Cynic once refuted a real P0 hardcoded secret because the wider repo lacked Stripe; recall fell 1.00→0.57). Reading the repo may only ADD nuance (a limiter actually wired, a `maxDuration` already set, a CDN header present), never ERASE an in-diff defect. This guardrail is load-bearing HERE: the "NOT A DEFECT — DO NOT FLAG / refute" directive above tells the Cynic to refute the calibrated non-defects (per-isolate limiter, 60/min limit, 60s timeout, Supabase tier) — it must NOT bleed into erasing a genuine in-diff MISSING/OVER-WIDE-limit, lost `Cache-Control`, or pool-contention defect.

Refute ONLY on: the finding targets a calibrated NOT-A-DEFECT (per-isolate limiter / 60-120 limits / 60s timeout / Supabase tier — cite the NOT A DEFECT row); the limiter IS wired on the path in the diff; a `maxDuration` override IS present; the route DOES set `s-maxage`+`stale-while-revalidate`; or the issue is really SEARCH/DATABASE's bottleneck → `out of scope: search/database`. Do NOT refute an in-diff missing limit/timeout/header just because the repo elsewhere has one — the deciding fact is the diff.
