# Family: CRON, SELF-HEALING & RELIABILITY

**Lens:** cron handlers, self-healing workers, scheduler correctness, operational safety. **Roles:** substitute `{{FAMILY}}=cron-reliability`.
**Glob triggers:** `**/selfheal/**`, `**/self-healing/**`, `vercel.json`, `**/workers/**`, `**/cron*`, `**/runLog*`
**Content signals:** `cron`, `CRON_SECRET`, `is_active`, `serviceProbe`, `schedule`, `deactivat`, `missingFromFeed`

## Seed checklist (coverage floor — grows via /35398)
1. **Health probe treats 4xx as healthy** — `status >= 200 && status < 500` counts 401/403/404 as "ok" (D14, still OPEN in repo). Fix: only 2xx (and explicitly-allowed 3xx) are healthy.
2. **No circuit breaker / backpressure** on a probe or worker that calls a flaky dependency (D8/D20).
3. **Run-logger loses the run record on insert failure** → silent failures, no observability (D16).
4. **No alert on cron failure** — a worker that can 100%-fail with nobody notified (D5).
5. **Scheduler race / duplicate schedules** — overlapping cron entries or a second scheduler (pg_cron/Edge/Action) doing the same work (B23 / BLOCKING-5).
6. **Destructive worker without a kill-switch** — mass `is_active=false` / deactivation with no `SELF_HEAL_*_DISABLE` guard (D15/B18).
7. **TTL too long / cutoff missing** — expiry/staleness with no age predicate (D10) — overlaps Database.
8. **`.limit()` with no `ORDER BY`** in a worker query → no fairness/progress (D17) — overlaps Database.
9. **Fail-open auth** — cron secret check that passes when the env var is unset (F2/D2).

## Cynic tuning
Refute on: the worker is read-only (no destructive write); a kill-switch exists elsewhere; the schedule overlap is intentional/idempotent. Watch items that are really Database (kick them over).

## Researcher tuning
Tier-2 focus: Vercel cron semantics + `CRON_SECRET` header model, idempotency of repeated worker runs, what a 4xx vs 5xx actually means for the probed dependency. Confirm kill-switch env-var names against the repo (`our-code` tier).
