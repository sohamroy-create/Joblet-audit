# Family: MIDDLEWARE & SCALABILITY  (Phase-5 — STUB; needs load-test calibration)

**Lens:** middleware, caching, connection pooling, frontend↔backend scalability. Substitute `{{FAMILY}}=middleware-scalability`.
**Glob triggers:** `middleware.ts`, `**/middleware/**`, `**/rate-limit*`, `vercel.json`, `lib/db*`, `**/*pool*`, `**/cache*`
**Content signals:** `new Map(`, `Cache-Control`, `rateLimit`, `pool`, `Supavisor`

## Seed checklist (TODO — Phase 5; thresholds need measured baselines)
1. Per-instance `Map` cache / rate-limiter that doesn't survive serverless fan-out (A7/A19).
2. Cron + ingest + live traffic contending on the connection pool (D19/B25).
3. No backpressure in a worker (D20/D8).
4. Missing/short `Cache-Control` on SSR (A2); SSR not reflecting query params (A3).
5. Request without timeout (29.6.3); no request-size limit (29.4.3).
_All latency/throughput thresholds tagged "uncalibrated — estimate only" until Task 5 load test lands._
