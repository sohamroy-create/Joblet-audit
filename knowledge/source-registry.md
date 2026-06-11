# Researcher knowledge source registry (Phase 3)

Maps each family to the authoritative sources the Researcher consults, by tier. Every Researcher claim cites its tier + a specific source; an untagged claim is an assumption, not evidence.

## Tier model (recap)
1. **our-code** — repo@HEAD, the diff, DB schema. Reachability ("is this path hit with attacker/real input?").
2. **canonical-docs** — CS/DSA texts + official docs for our stack.
3. **current-practice** — StackOverflow, GitHub issues, changelogs, CVEs/advisories.
4. **frontier** — for genuinely novel tech in the diff: latest advances + known pitfalls.

## Family → preferred sources (tiers 2–4)
| Family | Canonical-docs | Current-practice signals |
|---|---|---|
| security | PostgREST filter grammar; Firebase Auth (email_verified, uniqueness modes); Supabase RLS; OWASP (IDOR/CSRF/XSS) | CVEs for `@supabase/*`, `firebase`; OWASP cheat sheets |
| database | PostgREST ordering/pagination; supabase-js thenable execution model; Postgres index/`EXPLAIN`; CLRS (complexity) | supabase-js GitHub issues on `await`/upsert races |
| search | Postgres FTS/GIN/trigram; `pgvector`; Reciprocal-Rank-Fusion | pgvector issues; RRF write-ups |
| frontend-seo-aeo | Next.js 14 App Router metadata/canonical/SSR; React effect cleanup; CSP spec; schema.org JobPosting | Google Search Central; web.dev CSP |
| middleware-scalability | Vercel Fluid/Edge limits; Supavisor pooling; Cache-Control semantics | Vercel docs/changelog (Phase 5) |
| cron-reliability | Vercel Cron + `CRON_SECRET` model; idempotency patterns; HTTP status semantics | Vercel cron issues |

## Novelty mode — when to escalate to tier 4
Trigger novelty research when the diff introduces a dependency/pattern/API **not present** in the family's known set (new import, new framework primitive, a technique the checklist doesn't name). Output a short "state-of-the-art + pitfalls" brief BEFORE the family finalizes, tagged `frontier` with citations. This directly counters reasoning against stale assumptions (RC6/RC7).

## Citation + caching discipline
- Citation format: `tier · source-name · (section/URL/CVE-id)`.
- Performance claims are ALWAYS tagged `estimate — verify in staging` (no `EXPLAIN`/load test possible from the skill). Never present an estimate as measured (RC3).
- **Cache** common lookups (Firebase email_verified behavior, supabase-js await semantics, etc.) in `knowledge/cache.jsonl` keyed by question-hash, so repeat tie-breaks don't re-research. Cache entries carry a `checked_on` date; entries older than 90 days are re-validated.
- Confidence is mandatory (0.0–1.0); below 0.5 → return `partial` and let the human decide.
