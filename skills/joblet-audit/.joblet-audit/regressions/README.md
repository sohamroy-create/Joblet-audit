# Regression cases

One JSON file per case under `<family>/<id>.json`. A `knowledge` lesson can only be promoted to an active checklist rule (via `/35398`) if its paired `should_catch` case flips **FAIL→PASS** when the rule is added, and any `should_ignore` cases stay clean. See `orchestrator/learning-loop.md`.

Cases also double as the eval corpus for the bake-off (held-out subset kept separate).
