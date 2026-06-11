# Root causes — why the original audit missed/erred (Checker recall fuel)

Full version: `audit-project/artifacts/WHY_THE_AUDIT_WAS_WRONG.md`. Summary the Checkers load to bias toward recall:

- **RC1 — client-side blind spot.** Browser is a trust boundary. Check token stores, raw-HTML renders, client route guards, useEffect races.
- **RC2 — authorization, not just authentication.** For every user-scoped read/write: is the resource id from the verified token or from client input? Client → IDOR.
- **RC3 — never assert performance you didn't measure.** Tag measured/estimated/assumed. Researcher converts assumed→grounded.
- **RC4 — don't soften severity.** Default pessimistic when unsure (Cynic enforces).
- **RC5 — run the boring checklist first**, then hunt. CSRF/size-limits/timeouts/error-leakage are easy to overlook.
- **RC6 — reason against the live diff/HEAD**, never a remembered state. Cite file:line.
- **RC7 — a state/timing mismatch is not a correctness error** when contradicting an external source.
- **RC8 — single-pass reasoning ships plausible-but-wrong findings.** Hence the Cynic on every finding.
