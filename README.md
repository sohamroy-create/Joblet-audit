# joblet-audit — skill package (Phase 0 scaffold)

A distributable Claude Code skill that reviews code changes for the Joblet job-board against the project's own audit history, using a multi-agent family loop. No Claude API key needed — it runs inside each user's Claude Code.

## Layout
```
joblet-audit-skill/
  SKILL.md                 # orchestrator brain — how a review runs
  commands/                # 5 entry points: Joblet-review, 34287, 35398, 46408, 456098
  roles/                   # checker / cynic / researcher / analyser templates ({{FAMILY}}-parameterized)
  families/                # per-family defs (globs + seed checklist + tuning); security+database full, rest stubbed
  orchestrator/            # routing.json, output-contract.md, json-schemas.md
  scripts/                 # extract-diff.sh, corpus-sync.sh
.joblet-audit/             # SHARED CORPUS — ships to the TARGET repo, not the skill (syncs via git)
  findings.jsonl, root-causes.md, lessons.jsonl, quarantine.jsonl, config.json, checklists/
```

## Install (intended)
1. Distribute as a Claude Code **plugin** so the skill + the 5 commands install together and are namespaced (not loose global commands). 
2. Copy `.joblet-audit/` into the target repo (`Joblet-Official/joblet1.0`) on the `joblet-audit-corpus` branch — this is the shared, version-controlled knowledge base.
3. Approver/Source key hashes set during install via `/456098`. Read-only provider tokens go in each approver's LOCAL env.

## Status
- **Phase 0 (this):** scaffold, corpus structure, role templates, orchestrator/routing, output contract, command surface. Security + Database families seeded; others stubbed.
- **Phase 1 (next):** Family A end-to-end + the held-out false-negative eval set + the bake-off gate.
- Mechanics proven in Phase −1 (`agent/spike/SPIKE_RESULTS.md`).

## Known open flags
See `agent/FLAG_LEDGER.md`.
