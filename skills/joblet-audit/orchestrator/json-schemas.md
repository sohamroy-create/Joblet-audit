# Inter-role JSON contracts (strict — spike-proven)

The canonical wire format between roles. **Every role emits STRICT JSON ONLY** — no prose, no markdown fences. The Orchestrator parses each output and hands it to the next role. **Malformed JSON = role failure → the finding drops to `needs-human` (noted visibly, never silent).** These contracts must match `roles/{checker,cynic,researcher,analyser}.md` byte-for-byte; where this doc and a role file disagree, fix the doc.

## Shared invariants (all contracts)
| Field | Type / domain | Rule |
|---|---|---|
| `family` | one of `security \| database \| search \| frontend-seo-aeo \| middleware-scalability \| cron-reliability \| generalist` | the 7 families exactly |
| `severity` | exactly `P0 \| P1 \| P2` | P0 = exploit/data-loss/outage/SEO-deindex (block); P1 = serious correctness/perf/reliability under real load/input; P2 = lower-impact/hygiene |
| `id` / `finding_id` / `trigger_finding` | `<FAM>-N` (e.g. `security-1`, `db-2`) | **stable across the whole run** so Cynic/Researcher/Analyser can reference it |
| `confidence` | float `0.0–1.0` | mandatory where present |
| `*_if_changed` / `null` fields | JSON `null` (not `"null"`) | absent value is literal `null` |

Flow: **Checker → (Orchestrator) → Cynic → (Orchestrator, only on `needs-research`) → Researcher → (Orchestrator) → Analyser.** The Researcher is the slow/expensive tier and fires only on Cynic `needs-research` or diff novelty.

---

## 1. Checker → (Orchestrator → Cynic)
One object per family run. Emitted by `roles/checker.md` after the CHECKLIST pass (coverage floor) then the OPEN-ENDED HUNT pass (recall-graded).
```json
{"family":"<name>","findings":[
  {"id":"<FAM>-N","severity":"P0|P1|P2","file":"path:line","line":"approx",
   "claim":"short title","why":"runtime/exploit consequence",
   "suggested_fix":"concrete fix","pass":"checklist|hunt","confidence":0.0}
]}
```
| Field | Meaning / rule |
|---|---|
| `file` | REAL `file:line` against the current repo. Use `api-handlers/` (never `api/`); canonical table `jobs_joveo_partner_v2`. No stale paths. |
| `pass` | `checklist` = matched a known anti-pattern / active rule (the floor); `hunt` = new logic/runtime/scale bug on no list (false-negative defense). |
| `why` | the runtime / under-load / under-input / exploit consequence — not a style note. |
- **Empty is valid and correct:** `{"family":"<name>","findings":[]}`. Never invent issues to fill space; never flag pure style/formatting/CSS or pure renames.
- Perf claims are ESTIMATES except the MEASURED staging load test (2026-06-11): search p95 ~60s (`ILIKE '%term%'` seq scan → Vercel 60s timeout), autocomplete p95 ~2.5s, DB ~40 req/s. The rate limiter (60/min/IP API, 120/min pages, per-isolate) is **correct by design** — do not flag it.

---

## 2. Cynic → (Orchestrator → Researcher, only for `needs-research`)
One verdict per Checker finding, **same `id`**. The Cynic is always fed its Checker's JSON verbatim AND the exact diff/snippet each finding refers to (MANDATORY — without the artifact it over-refutes by checking the wrong thing, RC8).
```json
{"family":"<name>","verdicts":[
  {"id":"<FAM>-N","verdict":"stands|downgrade|refuted|needs-research",
   "severity_if_changed":"P0|P1|P2|null","reasoning":"1-2 sentences, diff-grounded"}
]}
```
| `verdict` | Meaning | `severity_if_changed` |
|---|---|---|
| `stands` | Genuine defect, severity correct. | `null` |
| `downgrade` | Real but over-rated; MUST give the corrected severity. | `P0\|P1\|P2` (required) |
| `refuted` | False positive / unreachable / already mitigated / out of THIS family's scope (state which). Hidden from report, kept for Analyser. | `null` |
| `needs-research` | Cannot settle from the diff alone; the deciding factor is an external/repo fact the Researcher must fetch. **THE ONLY verdict that triggers a Researcher call.** | typically `null` |

- **Artifact-scope rule (hard line):** judge each finding against the PROVIDED diff/snippet, NEVER refute an in-diff fact by repo-absence. (A buggy Cynic once refuted a real P0 hardcoded secret because the repo lacked Stripe; recall fell **1.00 → 0.57**.) Reading the repo may only ADD nuance, never erase an in-diff defect.
- Do not refute a genuine P0 without a concrete, diff-grounded reason. A finding belonging to another family is `refuted` with the correct family named (Orchestrator re-routes).
- Empty Checker input → `{"family":"<name>","verdicts":[]}`.

---

## 3. Researcher → Orchestrator
Fires ONLY on Cynic `needs-research` or diff novelty. **One object per finding**; does not scan the whole diff or re-run the Checker.
```json
{"finding_id":"<FAM>-N","ruling":"supports_checker|supports_cynic|partial",
 "final_severity":"P0|P1|P2","evidence":"the deciding facts",
 "source_tier":"our-code|canonical-docs|current-practice|frontier",
 "citation":"specific source(s)","confidence":0.0}
```
| Field | Meaning / rule |
|---|---|
| `finding_id` | echoes the Checker/Cynic `<FAM>-N` verbatim. |
| `ruling` | `supports_checker` (stands as framed) / `supports_cynic` (Cynic right — refute/downgrade) / `partial` (real but reframed/re-severitied). |
| `final_severity` | OVERRIDES Checker and Cynic; **never `null`** — the Researcher always settles a severity. Default pessimistic (RC4). |
| `source_tier` | `our-code` → `canonical-docs` → `current-practice` → `frontier`; tag the DEEPEST tier used. An untagged claim is an assumption, not evidence. |
| `citation` | specific source — real `file:line`, doc section, CVE, or `"load test, 2026-06-11"`. |

- **No CI:** the Researcher CANNOT run load tests / `EXPLAIN ANALYZE` against prod. Any NEW perf claim MUST be written inside `evidence` as **`"estimate — verify in staging"`** and never asserted as measured. The only MEASURED exception is the 2026-06-11 staging load test (search p95 ~60s; autocomplete ~2.5s; DB ~40 req/s; fix = 3 `pg_trgm` GIN indexes on `jobs_joveo_partner_v2` → search p95 <1s; page LCP <1.5s is **ESTIMATED**).
- Severity floors enforced: `.limit()` w/o `ORDER BY` on a large table = **P1** (`db-reg-1`); hardcoded secret / admin-client + user input / unsanitized `.or()` reachable by user input = **P0**; fail-open cron auth = **P0**; prod CSP `unsafe-eval`/`unsafe-inline` = **P0**.

---

## 4. Analyser → quarantine.jsonl
One object per proposed lesson, **APPENDED** to `.joblet-audit/quarantine.jsonl`. The Analyser learns WHAT the system knows — never HOW it thinks.
```json
{"family":"<name>","type":"knowledge|regression","proposed":"the rule or case",
 "reason":"what went wrong this run that this fixes","trigger_finding":"<FAM>-N",
 "conflicts_with":"<existing rule id or null>","regression_ref":"<path or null>",
 "requires":"/35398|/456098","status":"quarantined","ts":"<date>"}
```
| Field | Meaning / rule |
|---|---|
| `type` | `knowledge` = new/sharpened checklist rule or severity heuristic; `regression` = a minimal bad/good diff for the eval corpus. |
| `status` | **ALWAYS `quarantined` on write** — the Analyser cannot make a lesson active. Promotion is via `/35398` and only if the paired regression case flips FAIL→PASS. |
| `requires` | `/35398` for a normal knowledge promotion; **`/456098`** if the lesson can only be realized by changing how the system thinks (agent logic / roles / routing / prompts) — and then `proposed`/`reason` must say so explicitly. |
| `regression_ref` | path to `.joblet-audit/regressions/<family>/<id>.json` or `null`. |
| `conflicts_with` | existing rule id if it contradicts/duplicates one (flagged for human in `/34287`, never auto-merged), else `null`. |

- The Analyser may NEVER propose a behavior change. Default when ambiguous = treat as BEHAVIOR (`requires:/456098`). Feedback rule: only an EXPLICIT accept/reject counts — an *ignore* is NOT a rejection.

---

## 5. Final merged finding (Orchestrator → report)
**Not a role output** — the Orchestrator's internal join, then rendered per `orchestrator/output-contract.md`. A surviving finding = Checker finding + Cynic verdict (+ Researcher ruling if any), **deduped across families** on the same `file:line` (e.g. a missing `await` flagged by both `security` and `database`), assigned to the correct family by scope, keeping the highest-confidence framing.

**Final severity precedence (later overrides earlier):** Checker `severity` → Cynic `severity_if_changed` (on `downgrade`) → Researcher `final_severity`.

**Source tag** = the deepest role that touched the finding:
| Path through the loop | Source tag in report |
|---|---|
| Static pre-pass hit (grep/AST, no agents) | `verified` / `[deterministic]` |
| Checker-only, or Cynic `stands`/`downgrade` without research | `claimed` |
| Researcher ran | `researched:<source_tier>` |
| neither claimed nor verified applies | `assumed` |

- A finding with no Researcher pass is `claimed` or `assumed` — **NEVER `verified`** (only the deterministic pre-pass earns `verified`).
- Cynic `refuted` findings are dropped from the report but RETAINED for the Analyser.
- Findings dropped on timeout (`needs-human`) or unresolved (`needs-research`) are listed visibly under "Not fully reviewed" — never silent.

---

## 6. Worked examples (grounded in real open findings)
Illustrative only — values trace to the verified-finding context (2026-06-11).

**E14 — unsanitized `.or()` via `supabaseAdmin` (still open).** Checker → Cynic `stands` (in-diff, account-takeover) → no research → report `claimed`, P0.
```json
{"family":"security","findings":[{"id":"security-1","severity":"P0","file":"src/lib/supabase.ts:187","line":"187","claim":"unsanitized .or() in saveUserToSupabase via supabaseAdmin","why":"attacker-controlled value reaches PostgREST .or() on the admin client → account-takeover / data exposure","suggested_fix":"sanitize via postgrestQuote before .or(); never interpolate user input into admin-client filters","pass":"checklist","confidence":0.9}]}
{"family":"security","verdicts":[{"id":"security-1","verdict":"stands","severity_if_changed":null,"reasoning":"The unsanitized .or() is present in the diff on the admin client; repo absence of a sanitizer elsewhere does not refute the in-diff defect."}]}
```

**D17 — `.limit()` with no `ORDER BY` (still open).** Checker emits **P1** (the `db-reg-1` floor); Cynic `stands`; if it hinged on table size it would be `needs-research`.
```json
{"family":"database","findings":[{"id":"database-1","severity":"P1","file":"scripts/self-healing/workers/applyLinkChecker.js","line":"approx","claim":".limit() with no ORDER BY on a large table","why":"non-deterministic row selection → silently skips/reprocesses rows under load","suggested_fix":"add explicit ORDER BY before .limit() (regression db-reg-1, min_severity P1)","pass":"checklist","confidence":0.85}]}
{"family":"database","verdicts":[{"id":"database-1","verdict":"stands","severity_if_changed":null,"reasoning":".limit() with no ORDER BY is present in the diff against a large table; db-reg-1 fixes this at P1, not P2."}]}
```

**Analyser lesson (knowledge, promotable via /35398).**
```json
{"family":"database","type":"knowledge","proposed":".limit() on a large table without a preceding ORDER BY is P1, not P2","reason":"Checker initially rated D17 P2; pessimistic-severity floor was under-applied","trigger_finding":"database-1","conflicts_with":null,"regression_ref":".joblet-audit/regressions/database/limit-no-order.json","requires":"/35398","status":"quarantined","ts":"2026-06-11"}
```
