# Static pre-pass — deterministic checks (NO agent calls)

Spec §3.4 / Step 3b. Mechanical, lint-grade checks with a single right answer. They run as grep/AST **before** the families fan out, never consume a Checker/Cynic call, and you do not refute a grep hit. Each match is emitted to the report tagged `[deterministic]` (highest confidence) and handed to the relevant family Checker as CONTEXT so the Checker does not re-derive it.

Grounded against `/tmp/joblet-src` on 2026-06-11. Paths use `api-handlers/` (not `api/`) and the canonical table `jobs_joveo_partner_v2`.

## Rule set (each = pattern + deterministic verdict + tag)

| ID | Check | Detection pattern | Verdict | Tag |
|---|---|---|---|---|
| S-CANON | Filter/pagination `app/jobs` page collapses canonical to bare `/jobs` instead of self-canonical | In `app/jobs/**/page.tsx`, `alternates.canonical` is a hardcoded `'/jobs'`/`'https://joblet.ai/jobs'` literal rather than the derived helper (current good ref: `app/jobs/page.tsx:59` `jobsListingCanonicalFromURLSearchParams(...)`, applied `:83`) | P0 SEO | `[deterministic]` |
| S-ROBOTS | `public/robots.txt` vs `app/robots.ts` disagree on allow/deny or host | Diff both sources. Current state agrees: both `Allow: /` + a Disallow list; `app/robots.ts:50` sitemap `https://joblet.ai/sitemap.xml`. Flag any allow/disallow/host divergence between the two | P0 SEO | `[deterministic]` |
| S-SITEMAP-SLASH | Sitemap `loc` trailing-slash mismatch vs canonical | grep sitemap builders (`app/lib/sitemapSupabase.ts`, `scripts/generate-sitemap.js`) for emitted URLs ending `/` while the page canonical has no trailing slash (or vice-versa). SEO-1/18 (trailing slash) is FIXED — this guards a regression | P0 SEO | `[deterministic]` |
| S-NOINDEX | `noindex` applied on a loading/skeleton state | grep `noindex` in components that render before data resolves (e.g. `src/components/job-listing/JobListingPage.tsx`, `src/components/JobDetails.tsx`); match where the `robots: { index:false }`/meta is in the pre-data/loading branch | P1 SEO | `[deterministic]` |
| S-CSP-EVAL | `unsafe-eval`/`unsafe-inline` in the PROD `script-src` | Parse `src/lib/csp.ts` `buildContentSecurityPolicy`. Current prod branch (`:60-62`) is correct: `'self' 'nonce-…' 'strict-dynamic'` (E3 FIXED; dev-only `unsafe-eval` at `:56` is fine). Flag if `unsafe-eval`/`unsafe-inline` appears on the `!isDev` script-src — regression detector | P0 | `[deterministic]` |
| S-CSP-CONNECT | `connect-src` contains a bare protocol wildcard | Parse `src/lib/csp.ts` `CONNECT_SRC_LIST`. **LIVE (E4):** bare `'https:'` (`:38`) and `'wss:'` (`:39`) widen `connect-src` to any host | P1 | `[deterministic]` |
| S-SELECT-STAR | `select('*')` in a `src/lib/*Service.ts` | grep `select('*')` under `src/lib`. **LIVE (E6):** `applicantService.ts`, `advertiserService.ts`, `adminService.ts`, `recruiterService.ts` (+ `src/lib/supabase.ts`). Over-fetch; per-row PII/column bloat | P1 | `[deterministic]` |
| S-CRON-SECRET-OPEN | Cron auth returns truthy when the cron secret is unset (fail-open) | AST/grep the cron guard. Reference impl `api-handlers/_lib/cronAuth.js:40-52` is fail-CLOSED in prod (`if (!expected) { if NODE_ENV==='production' return {ok:false} }`); its `getExpectedSecret()` chains `SELF_HEAL_CRON_SECRET`/`SELF_HEALING_CRON_SECRET`/`CRON_SECRET`. Flag any guard that returns `true`/`{ok:true}` when its secret env is missing without the prod guard — regression detector. Scope is ANY cron-auth guard, so also covers the `SEO_CRON_SECRET` guards in `api-handlers/seo/index-jobs.js` and `url-inspection-sample.js` (sibling secret, not part of the cronAuth.js chain) | P0 | `[deterministic]` |

## Detection notes (no inventing — anchor to these)
- **S-CSP-CONNECT and S-SELECT-STAR are the LIVE matches among the tracked OPEN findings** (E4 at `src/lib/csp.ts:38-39`; E6 across the 4 `*Service.ts` files + `supabase.ts`). S-NOINDEX may ALSO match the current tree: `src/components/JobDetails.tsx:649` renders `robots="noindex,follow"` in the `if (loading)` branch (the exact noindex-on-loading-state class) — defensible since it is not in the tracked OPEN findings, but the rule will fire on it. (`JobListingPage.tsx:1206` noindex is correctly gated on `isPaginatedUrl` — legitimate, not a match.) The remaining rules are regression detectors guarding already-fixed defects (E3 prod CSP, SEO-1/18 trailing slash, robots parity) — emit only on a NEW divergence introduced by the diff.
- Globs are filename-anywhere (`**/*Service.ts`, `**/csp.ts`), never folder-only — root-level scripts and generically-named files must still match (Spec §3.1).
- The static pre-pass owns the **deterministic SEO slice** of `frontend-seo-aeo` (the D1/D2 split); the agent loop owns frontend logic (CSP-as-regression nuance, `select('*')` reachability, `useEffect`/AbortController) and AEO.
- Out of scope for the pre-pass (agent families, not deterministic): `serviceProbe.js:37` 4xx-as-healthy (D14, cron-reliability), unsanitized `.or()` in `src/lib/supabase.ts:187` `saveUserToSupabase` (E14, security), un-`ORDER BY`'d worker reads. These need judgment; do not force them into a grep rule.

## Behavior
- Run all rules first. Each match → report **"Static checks"** block, `[deterministic]` source tag, no Checker/Cynic pass (you do not refute a grep hit; Spec §2.5 maps these to `verified`/`[deterministic]`).
- Pass every match to the relevant family Checker as CONTEXT so it skips re-derivation (S-CSP-* → security + frontend-seo-aeo; S-SELECT-STAR → frontend-seo-aeo + database; S-CRON-SECRET-OPEN → cron-reliability + security; S-CANON/S-ROBOTS/S-SITEMAP-SLASH/S-NOINDEX → frontend-seo-aeo).
- A `[deterministic]` finding is never dropped to a Cynic and never downgraded by repo-absence reasoning.
- Adding/removing a rule from this set is a **knowledge** change (`/35398`, regression-gated). Changing **how** the pre-pass runs (the grep/AST mechanism, ordering, tagging) is **behavior** (`/456098`, Source key).
