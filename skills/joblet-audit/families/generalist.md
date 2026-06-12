# Family: GENERALIST (fallback — always-on safety net)

**Scope (§3.2 + §4 item 7):** fallback recall safety-net. No static checklist; pure open-ended hunt graded for recall. Substitute `{{FAMILY}}=generalist`, `<FAM>=generalist` for finding ids (`generalist-1`, `generalist-2`, …).

**Guarantee:** no PR ever passes with zero families awake.

## Wake conditions (§3.2)

This family has `globs: ["**/*"]`, `is_fallback: true`, **no `content_signals`**, **no checklist**. The Orchestrator ALWAYS also wakes `generalist` when ANY of:

| Trigger | Why |
|---|---|
| A changed/deleted file matches NO other family's globs or signals | The bug may live in an unnamed file (lesson 1, RC) |
| The diff DELETES code | A removed guard/`await`/auth check has no glob to catch it |
| Routing is uncertain | "When unsure, wake everything"; over-waking is safe, under-waking is not |

## The two passes (§1 Step 4)

| Pass | Behavior |
|---|---|
| CHECKLIST | **None.** This family has no static checklist; the coverage floor is empty by design. Skip straight to the hunt. |
| OPEN-ENDED HUNT | Pure recall hunt. Reason about what the change DOES and surface any logic error, correctness bug, security risk, data hazard, or reliability defect **regardless of domain**. Every finding is `"pass":"hunt"`. |

The bake-off edge is COVERAGE DISCIPLINE + DOMAIN KNOWLEDGE (recall 1.00 vs 0.85 no-knowledge baseline). With no checklist, the generalist's only job is the hunt — grade yourself on recall, not on filling space.

## What the hunt must catch (the false-negative classes the audit MISSED)

These are the team-caught / audit-missed bug styles (CONTEXT, "TEAM CAUGHT"). The generalist exists so these are caught even when no specialist family wakes. Each is a *pattern* to recognize, NOT a static rule — name the file:line in the diff:

| Pattern | Class | Example anchor (CONTEXT) |
|---|---|---|
| Deleted/removed guard, `await`, auth check, or kill-switch | regression via deletion | (any diff that removes a check) |
| Endpoint trusts a client-supplied id (userId/UID) without server auth | IDOR / authz | 29.2.3 `/api/user-profile` any UID; 29.2.4 onboarding trusts client userId |
| State-changing request with no CSRF/origin defense | CSRF | 29.3.2 |
| Token / secret stored in `localStorage` | credential exposure | 29.2.2 |
| Raw user HTML rendered without sanitization | XSS | 29.7.1 blog raw HTML |
| XML parsed with external entities enabled | XXE | 29.8.5 XML ingest |
| `useEffect` fetch without AbortController/cleanup | leak / race | 29.6.1 |
| `BUILD_ID` / artifact divergence between build & serve | deploy correctness | 29.8.1 |
| Un-awaited fire-and-forget write, unchecked `{data,error}` | silent data loss | (DB-class leaking into unnamed files) |

If a finding clearly belongs to a specialist family by scope, still RAISE it — the Orchestrator dedups and scope-routes post-hoc (§1 Step 6). Under-reporting is the failure mode, not duplication.

## Severity (§5.2 — applies to generalist findings too)

- **Default pessimistic when unsure** — the Checker historically under-rated (RC4); round severity UP, not down.
- Hardcoded secret / admin-client-with-user-input / unsanitized `.or()` reachable by user input / fail-open auth (cron secret passes when env unset) / prod CSP `unsafe-eval`|`unsafe-inline` = **P0**.
- `.limit()` with no `ORDER BY` on a large table = **P1** (not P2), anchored by `db-reg-1`.
- A deleted guard whose removal is exploitable or causes data loss = **P0**; otherwise P1.

## Roles still apply (§1, §2, §5.2)

| Role | Behavior for this family |
|---|---|
| Checker | `roles/checker.md` + this file. Hunt only; emits Checker JSON (§2.1). Empty is valid: `{"family":"generalist","findings":[]}`. Do not invent issues; do not flag pure style/CSS. |
| Cynic | `roles/cynic.md`, fed the Checker JSON verbatim AND the exact diff each finding refers to (MANDATORY, RC8). **Artifact-scope rule (§5.2):** judges each finding against the PROVIDED diff/snippet; never refutes an in-diff fact by repo-absence (a buggy Cynic once refuted a real P0 secret because the repo lacked Stripe; recall 1.00→0.57). Repo context may only ADD nuance, never erase an in-diff defect. |
| Researcher | NOT run by default (FAST mode). Fires ONLY on Cynic `needs-research` or diff novelty (unfamiliar library/pattern). Source-tagged; perf claims = `"estimate — verify in staging"` (except the §5 MEASURED load-test numbers). |

## Boundaries (cross-cutting)

- Use real `file:line` against the current repo; `api-handlers/` (not `api/`); `jobs_joveo_partner_v2` (canonical table). Do not cite stale paths or invent findings.
- This family proposes lessons to QUARANTINE only (§6.1); it has zero power over active corpus, keys, or agent logic. Behavior changes require `/456098` (§6.4).
- No code grounding ships in this file by design: the generalist carries no checklist and no fixed findings — its recall comes from open-ended reasoning over the diff, not a baked-in list.
