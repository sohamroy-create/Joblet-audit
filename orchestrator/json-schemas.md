# Inter-role JSON contracts (strict — proven in Phase −1 spike)

All roles emit **strict JSON only** (no prose, no markdown fences). The Orchestrator parses and passes these between roles.

## Checker → (Orchestrator → Cynic)
```json
{"family":"<name>","findings":[
  {"id":"<FAM>-N","severity":"P0|P1|P2","file":"path","line":"approx",
   "claim":"string","why":"string","suggested_fix":"string",
   "pass":"checklist|hunt","confidence":0.0}
]}
```

## Cynic → (Orchestrator → Researcher, only for needs-research)
```json
{"family":"<name>","verdicts":[
  {"id":"<FAM>-N","verdict":"stands|downgrade|refuted|needs-research",
   "severity_if_changed":"P0|P1|P2|null","reasoning":"string"}
]}
```

## Researcher → Orchestrator
```json
{"finding_id":"<FAM>-N","ruling":"supports_checker|supports_cynic|partial",
 "final_severity":"P0|P1|P2","evidence":"string",
 "source_tier":"our-code|canonical-docs|current-practice|frontier",
 "citation":"string","confidence":0.0}
```

## Analyser → quarantine.jsonl (one object per lesson)
```json
{"family":"<name>","type":"knowledge|regression","proposed":"string",
 "reason":"string","trigger_finding":"<FAM>-N","conflicts_with":"id|null",
 "regression_ref":"path|null","requires":"/35398|/456098",
 "status":"quarantined","ts":"date"}
```

## Final merged finding (Orchestrator → report)
A surviving finding = Checker finding + Cynic verdict (+ Researcher ruling if any), deduped across families, with the final severity. Refuted findings are dropped from the report but logged for the Analyser.
