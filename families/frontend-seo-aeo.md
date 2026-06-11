# Family: FRONTEND, SEO & AEO

**Token:** `frontend-seo-aeo` (finding ids `frontend-seo-aeo-N`). **Roles:** substitute `{{FAMILY}}=frontend-seo-aeo`.
**Scope (one line):** SEO/AEO correctness + frontend logic hygiene, with the D1/D2 split — SEO is DETERMINISTIC (owned by the static pre-pass, not the agent loop); the agent loop owns frontend logic (CSP regressions, `select('*')` over-fetch, `useEffect` without AbortController/cleanup, unprotected routes, raw-HTML/JSON-LD XSS) and AEO readiness (advisory).

## Wake rule (routing.json — glob OR content-signal)
- **globs (filename-anywhere):** `app/**`, `**/components/**`, `**/*.tsx`, `next.config.*`, `**/*robots*`, `**/*sitemap*`, `**/*csp*`, `src/lib/*Service.ts`, `**/*JsonLd*`, `**/*JobDetail*`
- **content_signals:** `canonical`, `noindex`, `JsonLd`, `ld+json`, `dangerouslySetInnerHTML`, `useEffect`, `AbortController`, `select('*')`, `connect-src`, `unsafe-eval`, `metadata`, `formatBlogContentForDisplay`
- Over-waking is safe; under-waking is not. The Orchestrator dedups overlaps (e.g. an XSS row this family and Security both raise on the same `file:line`); blog/JSON-LD XSS rows are SHARED-SCOPE with `security` — keep the highest-confidence framing, do not double-count.

---

## THREE sub-lenses, three different handlings (the D1/D2 split — KEEP the split)

### Sub-lens 1 — SEO (DETERMINISTIC → static pre-pass, NO agent calls)
Mechanical, definite-right-answer checks. They run as grep/AST in `orchestrator/static-checks.md` BEFORE families fan out, emit to the report tagged `[deterministic]`, and are handed to this Checker as CONTEXT. The Checker **reviews** the static output for nuance — it does NOT re-derive these (a Checker that re-flags a grep hit wastes a call and a Cynic cannot refute a grep).

| Static ID | Check | Verdict | Current repo status (2026-06-11) |
|---|---|---|---|
| S-CANON | filter/pagination page collapses canonical to `/jobs` instead of self-canonical | P0 SEO | watch only |
| S-ROBOTS | `app/robots.ts` DISALLOW vs `public/robots.txt` disagree (host/allow/deny) | P0 SEO | lists MATCH per design; dual-source drift is a standing footgun (see frontend-logic row F7) |
| S-SITEMAP-SLASH | sitemap URL trailing-slash mismatch vs canonical | P0 SEO | `next.config.mjs:17 trailingSlash:false` — SEO-1/18 FIXED |
| S-NOINDEX | `noindex` on a loading/skeleton state | P1 SEO | watch only |
| S-CSP-EVAL | `unsafe-eval`/`unsafe-inline` in PROD `script-src` | P0 | `csp.ts:62` prod = `'nonce' 'strict-dynamic'`; eval gated behind `isDev` (`csp.ts:56`) — E3 FIXED |
| S-CSP-CONNECT | `connect-src` bare wildcard `https:`/`wss:` | P1 | **HIT → see F1 below** (`csp.ts:36-53`) |
| S-SELECT-STAR | `select('*')` in `src/lib/*Service.ts` | P1 | **HIT → see F2 below** (E6, OPEN) |

Adding/removing a static rule is KNOWLEDGE (`/35398`); changing HOW the pre-pass runs is BEHAVIOR (`/456098`).

### Sub-lens 2 — Frontend logic (AGENT loop — the real Checker → Cynic work)
Each row must tie to a runtime/exploit consequence (no style/CSS findings). Severities default pessimistic when blast radius is ambiguous (Checker historically under-rated, RC4).

| Ref | Check | Where (current file:line) | Sev | Status |
|---|---|---|---|---|
| F1 | CSP `connect-src` opens with `'self','https:','wss:'` BEFORE the granular Supabase/Firebase/Google hosts → two wildcards make the allowlist moot; a compromised/injected script can beacon to ANY https/wss origin. Emitted in prod (no `isDev` gate on the wildcards). | `src/lib/csp.ts:36-53` (`CONNECT_SRC_LIST`); emitted at `csp.ts:73` | **P1** | E4 OPEN. P1 per the canonical static rule S-CSP-CONNECT (`[deterministic]`, §3.4). Surfaced by the static pre-pass — keep ONE row, prefer `[deterministic]` framing; the agent loop does NOT down-rate a deterministic grep hit (§3 step 3b). |
| F2 | `select('*')` over-fetch in service modules → ships unneeded columns / PII over the wire. | `adminService.ts:39`, `applicantService.ts:129/263/590/704`, `recruiterService.ts:36`, `advertiserService.ts`, `supabase.ts` — **11 occurrences / 5 files** | **P1** | E6 OPEN. Owned by S-SELECT-STAR static pre-pass — Checker does NOT emit a separate row; cite count as "11 occurrences / 5 files" (NOT "11 files"). |
| F3 | Blog body rendered as raw HTML with NO sanitization → stored XSS. `formatBlogContentForDisplay()` doc comment itself states "Does not strip tags". No DOMPurify/sanitize-html anywhere. `<script>`/`<img onerror=…>` in a post body executes in visitors' browsers. | live path `app/blog/[slug]/page.tsx` → `blog-post-client.tsx:5` → `src/routes/BlogPost.tsx:650` `dangerouslySetInnerHTML={{__html: blogBodyHtmlWithAnchors}}`; source `src/lib/stripHtml.ts:287-290` | **P1** | 29.7.1 OPEN — a team-caught / audit-MISSED false-negative class; the open-ended HUNT pass MUST catch this style. Legacy Vite route is the CURRENT live renderer via the App Router wrapper (not dead code). Shared-scope with `security`. |
| F4 | JSON-LD on `/jobs` listing serialized with NO `</script>` escape. Graph embeds `job.title`, `companyName(job)`, `jobPostingDescription(job)` from `jobs_joveo_partner_v2` (partner XML feeds, untrusted) → `</script><script>…` breaks out of the `ld+json` block. The sibling job-DETAIL builder DOES escape (`.replace(/</g, '<')`, escaping `<` to the JSON unicode escape) — this is the unfixed sibling in the JSON-LD detail-vs-listing escape gap (fixed-sibling/unfixed-sibling class). | `app/jobs/page.tsx:160` `JSON.stringify(jobsJsonLdGraph)` (graph lines 121-132); escaped sibling `src/lib/buildJobDetailJsonLd.ts:328,365` | **P1** | OPEN, NEW vs prior status. Stored XSS on a high-traffic crawlable page. Per Cynic ARTIFACT-SCOPE rule: breakout vector is fully present in the cited file; the escaped siblings only ADD evidence it was deliberate-but-incomplete. Shared-scope with `security`. |
| F5 | JSON-LD on category/role listing pages serialized without `</script>` escape (consistency sibling). Embedded value is `name` (slug from URL path), not free-text DB content → narrower breakout surface than F4. | `app/jobs/category/[slug]/page.tsx:83`, `app/jobs/role/[slug]/page.tsx:77` | **P2** | OPEN. Same un-escaped pattern the blog + job-detail paths correct; lower-impact hygiene (slug-only input, narrow surface). |
| F6 | Partner job-description sanitizer is regex-based and misses event-handler attrs. Strips `<script>/<style>` + `style=` and blocks `javascript:` hrefs, but does NOT remove `onerror=/onload=/onmouseover=` → `<img src=x onerror=…>` from a partner feed survives and renders. | sanitizer `src/lib/stripHtml.ts:66-75`; render sink `JobDetails.tsx:1615,1627` `dangerouslySetInnerHTML={{__html: jobDescriptionHtml}}` | **P2** | PARTIAL mitigation (real, not a full fix). Unlike F3 it at least removes script tags. Shared-scope with `security`. |
| F7 | `useEffect` fetch with NO AbortController/cancellation → out-of-order responses (stale overwrites fresh) + setState-after-unmount. `search()` is invoked from 3 effects (mount, `radius` change, `gpsCoords` change); rapid radius/GPS changes issue overlapping requests. | `app/jobs-near-me/JobsNearMeClient.tsx` `search()` lines 120-154, effects 175-188; same class in `src/components/CustomChatbot.tsx`, `ForgotPasswordModal.tsx`, `src/routes/LocationsDirectory.tsx`, `DirectJobApply.tsx` | **P2** | 29.6.1 OPEN — team-caught / audit-MISSED false-negative class; HUNT pass MUST catch it. |
| F8 | Unprotected admin/employer client routes — guard exists only client-side or not at all (auth check renderable but bypassable). | `app/**` admin/employer route components + their loaders | **P1 if reachable** | watch — confirm the route's server-side gate before rating; client-only guard = P1. |
| F9 | `next.config.mjs` ships a "TEMP DIAGNOSTIC" `console.log` of env at every boot. Only public `NEXT_PUBLIC_*` values + a length printed (no secret leak), but flagged TEMP and left in prod config. | `next.config.mjs:7-13` | **P2** | OPEN — lower-impact hygiene: log noise / minor info disclosure in build logs. |
| F10 | robots dual-source maintenance hazard: `app/robots.ts` is only a FALLBACK; `public/robots.txt` is served first. DISALLOW edits in the route silently no-op in prod unless the static file is also edited. | `app/robots.ts:7-15` (DISALLOW array 16-31) | **P2** | OPEN — not a defect now (lists match per design intent); lower-impact hygiene, a standing footgun for the checklist. |

### Sub-lens 3 — AEO (ADVISORY ONLY — no ground truth, never a graded P0/P1/P2)
Emit as `advisory` notes only: nothing for the Cynic to refute, no regression case, no severity. The Checker lists them; they never enter the severity-graded report body.
- JSON-LD `JobPosting` structured-data presence/validity (note: validity ≠ the F4/F5 escape defect, which IS graded).
- Crawlable server-rendered content for AI answer engines (SSR vs client-only fetch).
- Clean semantic heading hierarchy.

---

## Load-test ground truth (MEASURED, staging 2026-06-11 — treat as fact)
- autocomplete p95 budget < 100ms — **MEASURED ~2.5s** (breaches; functional but slow).
- search p95 budget < 300ms — **MEASURED ~60s** (ILIKE `'%term%'` → seq scan → Vercel 60s timeout). Owned by `search`/`middleware-scalability`, not this family — do not re-flag here.
- page LCP < 1.5s — **ESTIMATED** target unless a measured number is cited.
- Rate limiter (60/min/IP API, per-isolate, in-memory) is CORRECT BY DESIGN — do NOT flag. Leave the 60/min limit, 60s timeout, Supabase tier ALONE.
- This family makes only static/code-grounded claims (XSS, CSP, races, over-fetch). It asserts NO load-test/EXPLAIN measurement of its own; any NEW perf claim a Researcher adds is tagged `"estimate — verify in staging"`.

## Cynic tuning (`roles/cynic.md`)
- Judge each finding against the PROVIDED diff/snippet ONLY (ARTIFACT-SCOPE rule, lesson 2). Never refute an in-diff XSS/CSP fact by repo-absence; reading the repo for CONTEXT may only ADD nuance (reachability, mitigation), never erase an in-diff defect. (A buggy Cynic once refuted a real P0 by repo-absence; recall 1.00→0.57.)
- `refuted` for any SEO item the static pass already settled (wrong family/scope).
- Challenge AEO items HARD — low ground truth, advisory-only, never graded.
- Hold every frontend-logic row to a real runtime consequence; F4/F5 escape claims stand on the missing `<` escape in the cited file regardless of the escaped siblings.

## Researcher tuning (`roles/researcher.md`) — fires only on Cynic `needs-research` or diff novelty
Tier focus: `our-code` (verify the live render path / sink) → `canonical-docs` (Next.js 14 App Router metadata/canonical/SSR, CSP spec, React effect-cleanup semantics, schema.org `JobPosting`) → `current-practice` (XSS escaping CVEs/OWASP) → `frontier`. Every claim source-tagged; perf claims `"estimate — verify in staging"`.

## Analyser → quarantine only
New lessons (e.g. "JSON-LD listing pages must apply the `<` escape the detail builder uses") append to `.joblet-audit/quarantine.jsonl` with a regression case under `.joblet-audit/regressions/frontend-seo-aeo/`. Promotion via `/35398` only if the `should_catch` case flips FAIL→PASS. Behavior changes (e.g. moving a check between static-pass and agent loop) tag `requires:/456098`.
