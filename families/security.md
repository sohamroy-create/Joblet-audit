# Family: SECURITY & AUTH

**Lens:** secrets, auth, authorization, injection, data exposure. **Roles:** checker, cynic, researcher, analyser (templates in `roles/`, substitute `{{FAMILY}}=security`).

**Glob triggers:** `**/api*/**`, `**/auth*/**`, `**/*.env*`, `middleware.ts`, `**/*supabase*`, `**/*firebase*`, `lib/api-key.*`, `**/csp*`
**Content signals:** `supabaseAdmin`, `service_role`, `verifyIdToken`, `.or(`, `localStorage`, `dangerouslySetInnerHTML`, `createClient`

## Seed checklist (the coverage floor — grows via /35398)
1. Hardcoded secret / JWT / service_role key in source (F1/E1).
2. service_role / admin client used where user input flows in, or imported into client code (E2).
3. Unsanitized PostgREST `.or()` / `.filter()` template-literal interpolation of user input — esp. via admin client (E14). Fix: `quotePostgrestOrFilterValue`.
4. **IDOR** — resource id taken from client input instead of the verified token (29.2.3/29.2.4). *(RC2 — historically missed.)*
5. Missing CSRF protection on state-changing routes (29.3.2).
6. Auth tokens in localStorage / XSS-exfiltratable (29.2.2).
7. Raw HTML render / `dangerouslySetInnerHTML` of user/blog content (29.7.1 XSS).
8. Error-detail / stack leakage to API clients (29.4.2).
9. Fail-open auth (cron/secret check passes when env unset) (F2/D2).
10. Account-linking by unverified email (Firebase `email_verified` not checked before linking).

## Cynic tuning
Refute on: not reachable with attacker input; already sanitized upstream; out-of-scope (data-integrity, not security). Be strict on exploitability claims; demand the actual attacker path.

## Researcher tuning
Tier-2/3 focus: PostgREST filter grammar, Firebase Auth guarantees (email uniqueness/verification), Supabase RLS semantics, relevant CVEs.
