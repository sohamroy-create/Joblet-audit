# Family: FRONTEND, SEO & AEO

**Lens:** SEO correctness, AEO (answer-engine) readiness, frontend logic hygiene. **Roles:** substitute `{{FAMILY}}=frontend-seo-aeo`.
**Glob triggers:** `app/**`, `components/**`, `src/components/**`, `**/*.tsx`, `next.config.*`, `**/robots*`, `**/sitemap*`, `**/csp*`, `src/lib/*Service.ts`
**Content signals:** `canonical`, `noindex`, `JsonLd`, `useEffect`, `select('*')`, `metadata`, `dangerouslySetInnerHTML`

This family has THREE sub-lenses with different handling (per BUILD_PLAN §4.5 — the D1/D2 split):

## Sub-lens 1 — SEO (DETERMINISTIC → handled by the static pre-pass, NOT the agent loop)
These are mechanical and have a right answer; they run in `orchestrator/static-checks.md` as grep/lint, cheaper and more reliable than agents:
- Canonical correctness: filter/pagination pages must self-canonicalize, not collapse to `/jobs` (SEO-2/19).
- `robots.txt` / `robots.ts` consistency across surfaces (SEO-17).
- Sitemap shape + trailing-slash hygiene (SEO-1/6).
- Accidental `noindex,follow` on loading states (SEO-3).
The Checker only *reviews the static-pass output* for context; it does not re-derive these.

## Sub-lens 2 — Frontend logic (AGENT loop — this is the real Checker/Cynic work)
1. CSP regression: `unsafe-eval`/`unsafe-inline` reaching production `script-src`, or over-wide `connect-src` wildcard (E3/E4/E16).
2. `select('*')` over-fetch in `src/lib/*Service.ts` (E6).
3. `useEffect` without AbortController/cleanup → race conditions / stale state (29.6.1).
4. Unprotected admin/employer client routes (29.6.2).
5. Raw HTML / `dangerouslySetInnerHTML` of user/blog content (XSS — overlaps Security).
6. New client-side data fetch that should be server-rendered (perf/SEO).

## Sub-lens 3 — AEO (ADVISORY ONLY — no ground truth, never a graded P0/P1)
- JSON-LD `JobPosting` structured-data presence/validity.
- Crawlable server-rendered content for AI answer engines.
- Clean semantic heading hierarchy.
Emit these as `advisory` notes, never as severity-graded findings (nothing for the Cynic to refute; no regression case).

## Cynic tuning
Refute SEO items that the static pass already settled; challenge AEO items hard (low ground truth). Hold frontend-logic items to a real runtime consequence.

## Researcher tuning
Tier-2 focus: Next.js 14 App Router metadata/canonical/SSR semantics, CSP spec, React effect cleanup semantics, schema.org JobPosting.
