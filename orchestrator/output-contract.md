# Output contract — the review report

`/Joblet-review` prints this to the terminal (post-MVP: posts as a PR comment).

## Header
```
Joblet-Audit review · <mode: fast|deep> · <N files, M findings> · <wallclock>
Families woken: <list>   |   Dropped/timed-out: <list or none>
```

## Findings — grouped by severity (P0 first), then family
For each surviving finding:
```
[P0] <family> · <file>:<line>
  <claim>
  Why:  <why / exploit / runtime consequence>
  Fix:  <concrete suggested fix>
  Conf: <0.0-1.0>   Source: <verified | claimed | assumed | researched:<tier>>
```

## Rules
- Only surviving findings appear (refuted ones are hidden but logged for the Analyser).
- Deduped findings show the single best framing + which families raised it.
- If anything was dropped to `needs-human` (timeout) or `needs-research` (unresolved), list it explicitly under a **"Not fully reviewed"** section — never silent.
- Footer: `Proposed lessons queued to quarantine: <count> (review via /34287, apply via /35398)`.
- Confidence/source tags are mandatory. A finding with no Researcher pass is `claimed` (Checker) or `assumed`, never `verified`.
