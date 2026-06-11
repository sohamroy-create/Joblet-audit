# Static pre-pass — deterministic checks (NO agent calls)

Per BUILD_PLAN §4.5, mechanical lint-grade checks with a definite right answer run here as cheap grep/AST checks BEFORE the agent families fan out. They never consume a Checker/Cynic call. Their output is attached to the report and given to the relevant family Checker as context (the Checker does not re-derive them).

## Rules (each = a pattern + a deterministic verdict)
| ID | Check | Detection | Verdict if matched |
|---|---|---|---|
| S-CANON | Filter/pagination page collapses canonical to `/jobs` instead of self-canonical | metadata/canonical in `app/jobs/**` page files | P0 SEO |
| S-ROBOTS | `robots.txt` vs `app/robots.ts` disagree (allow/deny, host) | diff both robots sources | P0 SEO |
| S-SITEMAP-SLASH | Sitemap URL has trailing slash mismatch vs canonical | grep sitemap builders for trailing `/` | P0 SEO |
| S-NOINDEX | `noindex` on a loading/skeleton state | grep `noindex` in components rendered before data | P1 SEO |
| S-CSP-EVAL | `unsafe-eval`/`unsafe-inline` in PRODUCTION `script-src` | parse `src/lib/csp.ts` prod branch | P0 |
| S-CSP-CONNECT | `connect-src` contains bare wildcard `https:`/`wss:` | parse csp `CONNECT_SRC_LIST` | P1 |
| S-SELECT-STAR | `select('*')` in `src/lib/*Service.ts` | grep | P1 |
| S-CRON-SECRET-OPEN | cron auth returns true when `CRON_SECRET` unset | grep cron auth guard | P0 |

## Behavior
- Run all rules; emit matches into the report under a **"Static checks"** block with `[deterministic]` source tag (highest confidence, no Cynic needed).
- A deterministic match is NOT sent through the Checker→Cynic loop (no point refuting a grep hit). It MAY be referenced by a family Checker for related reasoning.
- Adding/removing a static rule is a **knowledge** change (`/35398`); changing *how the pre-pass runs* is **behavior** (`/456098`).
