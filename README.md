# joblet-audit (Claude Code plugin)

Multi-agent code-review system for the Joblet job-board, calibrated to the project's audit history + a staging load test. Runs read-only inside Claude Code / Cowork; no API key.

## Install (Cowork or Claude Code)
```
/plugin marketplace add sohamroy-create/Joblet-audit
/plugin install joblet-audit@joblet-audit
/reload-plugins
```
(Cowork GUI: Customize → Plugins → Add marketplace → `sohamroy-create/Joblet-audit` → Install.)

## Commands (namespaced by the plugin)
| Command | Who | Purpose |
|---|---|---|
| `/joblet-audit:Joblet-review` | everyone, no key | review the current diff (or `--paste`); read-only; proposes lessons to quarantine |
| `/joblet-audit:34287` | reviewers, no key | render the quarantine queue as a weekly `.docx` |
| `/joblet-audit:35398` | Approver key | apply approved knowledge updates (regression-gated) |
| `/joblet-audit:46408` | Approver key | rotate read-only Vercel/Supabase/GitHub tokens (15-day) |
| `/joblet-audit:456098` | Source key (Soham) | change agent logic/source/behavior |

## Layout
- `.claude-plugin/` — `plugin.json` (manifest) + `marketplace.json` (listing)
- `commands/` — the 5 slash commands (plugin root)
- `skills/joblet-audit/` — the skill: `SKILL.md` (orchestrator brain), `roles/`, `families/`, `orchestrator/`, `knowledge/`, `scripts/`, and the seed `.joblet-audit/` corpus.

## First-run setup
1. Set key hashes (key holders, locally): `skills/joblet-audit/KEY_SETUP.md`.
2. The shared corpus syncs from the `joblet-audit-corpus` branch (`skills/joblet-audit/scripts/corpus-sync.sh`).

See `skills/joblet-audit/PRODUCT_DOCUMENTATION.md` for full scope/capabilities/structure.
