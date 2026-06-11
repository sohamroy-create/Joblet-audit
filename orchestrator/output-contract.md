# Output contract — the `/Joblet-review` report

The canonical, severity-graded report format. The Orchestrator (SKILL.md) emits this AFTER merge+dedup (Step 6) by joining each surviving finding (§2.5): Checker finding + Cynic verdict (+ Researcher ruling). Printed to the terminal in MVP; PR comment is post-MVP. Format rule: tight, table-friendly, no fluff. Ground every line in the artifact (the diff) and the corpus — do NOT invent issues, severities, or `file:line` to fill space.

---

## 1. Header (always printed)

```
Joblet-Audit review · <fast|deep> · <N files · M findings (P0:a P1:b P2:c)> · <wallclock>s/360s
Families woken: <comma list>          Static pre-pass: <K [deterministic] hits>
Dropped / timed-out: <list or "none">
```
- `wallclock` vs the `360s` budget (`per_run_wallclock_seconds`, §3.3 spec) makes timeout pressure visible.
- "Families woken" is the §3 wake result (glob OR content-signal; `generalist` if unclaimed file / deletion / uncertainty). Over-waking is expected — do not apologise for it.

---

## 2. Findings — grouped by SEVERITY (P0 first), then by FAMILY

Within each severity bucket, order by family, then by `confidence` descending. One block per surviving finding. `[deterministic]` static pre-pass hits print FIRST inside their severity bucket (highest confidence; never refuted).

```
[P0] security · src/lib/supabase.ts:187
  Unsanitized .or() in saveUserToSupabase via supabaseAdmin (account-takeover).
  Why:  user-controlled string reaches a PostgREST .or() on the admin client; the sibling
        api-handlers/_lib/postgrestQuote.js path was fixed but THIS one was not.
  Fix:  route through postgrestQuote.js / parameterize; never interpolate user input into .or().
  Conf: 0.95   Source: claimed         (id security-1)
```
Field grammar, in fixed order:
| Field | Source role | Rule |
|---|---|---|
| `[severity]` | final (§2.5) | `P0\|P1\|P2`. Cynic `severity_if_changed` overrides Checker; Researcher `final_severity` overrides both. |
| `family` | Orchestrator | the scope-routed owning family after dedup. |
| `file:line` | Checker | REAL path against current repo. Use `api-handlers/` (never `api/`) and `jobs_joveo_partner_v2`. `line` may be `~approx`. |
| `claim` | Checker | short title. |
| `Why` | Checker (+Researcher) | runtime / exploit / data-loss / deindex consequence — concrete, not "could be risky". |
| `Fix` | Checker | one concrete fix. |
| `Conf` | deepest role | float `0.0–1.0`. |
| `Source` | §2.5 derivation | tag below. |
| `(id …)` | Checker | stable `<FAM>-N` id, for cross-referencing. |

### Source-tag derivation (NEVER mislabel)
| Tag | When |
|---|---|
| `verified` / `[deterministic]` | static pre-pass hit (grep/AST); you do not refute a grep. |
| `claimed` | Checker-only, or Cynic `stands`/`downgrade` WITHOUT a Researcher pass. |
| `researched:<tier>` | a Researcher pass ran; tier ∈ `our-code\|canonical-docs\|current-practice\|frontier`. |
| `assumed` | survived but no role could ground it (e.g. role-failure fallthrough). |
A finding with NO Researcher pass is `claimed` or `assumed` — **never `verified`** (except deterministic pre-pass hits).

---

## 3. Performance-claim labelling (skill has no CI)

The Researcher CANNOT run load tests / `EXPLAIN ANALYZE` on prod. Any NEW perf claim prints `(estimate — verify in staging)` in its `Why`. The 2026-06-11 staging load-test numbers are the ONLY MEASURED exception and may be cited as fact:
- search p95 ~60s — `ILIKE '%term%'` substring → seq scan → hits Vercel 60s function timeout (THE bottleneck; confirms C15/A20/C18). Budget: search p95 < 300ms **(MEASURED)**.
- autocomplete p95 ~2.5s vs < 100ms budget **(MEASURED)** — functional but slow.
- DB sustains ~40 req/s before search latency climbs **(MEASURED)**.
- Fix: 3 `pg_trgm` GIN indexes on `jobs_joveo_partner_v2` (title, description, company) → search p95 60s→<1s **(MEASURED recommendation)**.
- page LCP < 1.5s budget **(ESTIMATED)** — label as such unless a measured number is cited.

DO NOT flag the rate limiter (60 req/min/IP API, 120/min pages, per-edge-isolate, in-memory) as a defect — it is **correct by design**; 87% 429 under single-source flood is intended bot defense. The defect class is MISSING / over-wide limits. Leave the 60/min limit, the 60s timeout, and the Supabase tier alone.

---

## 4. "Not fully reviewed" section (never silent)

Print this section whenever anything was dropped — omit only if empty. Refuted findings do NOT appear here (they are hidden from the report, retained for the Analyser).

```
── Not fully reviewed ──────────────────────────────────────────
needs-human   <family> · <file>:<line> · <id> · <reason: role timeout / malformed JSON>
needs-research <family> · <file>:<line> · <id> · <the external/repo fact that must be fetched>
```
- `needs-human`: a role exceeded its slice (timeout, §3.3 `on_timeout`) or emitted malformed JSON (role failure). Continue the run; surface it here. Never block the whole report on one hung agent; never drop silently.
- `needs-research`: in `fast` mode the Researcher is on-demand-only, so a Cynic `needs-research` verdict that did not get a Researcher pass lands here unresolved.

---

## 5. Quarantine footer (always last)

```
────────────────────────────────────────────────────────────────
Proposed lessons queued to quarantine: <count>   (review via /34287 · apply via /35398)
Mode: read-only. /Joblet-review changes NO active corpus, checklists, keys, or agent logic.
```
- The Analyser appends each lesson as `status:"quarantined"` to `.joblet-audit/quarantine.jsonl` (§2.4) — NEVER active here.
- Lessons that can only be realized by changing how the system thinks carry `requires:/456098` and say so; `/Joblet-review` does not attempt them.
- `<count>` is the number appended THIS run.

---

## 6. Hard rules for the emitter

1. Only **surviving** findings appear in §2. Refuted = hidden (logged for Analyser); dropped = §4; never silent anywhere.
2. **Deduped** findings (same `file:line` raised by multiple families, e.g. a missing `await` flagged by security and database) print ONCE under the scope-correct owner with the highest-confidence framing.
3. Confidence + source tag are MANDATORY on every finding. No `verified` without a static hit; no `researched:` without an actual Researcher pass.
4. Empty is valid: `0 findings` → print header, "No findings above style/formatting threshold.", and the footer. Do NOT manufacture findings.
5. Never flag pure style / formatting / CSS changes.
6. Severity follows the rubric: `.limit()` with no `ORDER BY` on a large table = **P1** (not P2; regression `db-reg-1`); hardcoded secret / admin-client-with-user-input / unsanitized `.or()` reachable by user input = **P0**; fail-open cron auth = **P0**; CSP `unsafe-eval`/`unsafe-inline` in prod = **P0**. Default pessimistic when blast radius is ambiguous.
