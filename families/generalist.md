# Family: GENERALIST (fallback — always available)

**Purpose:** the recall safety-net. Wakes when a changed/deleted file matches no other family, or routing is uncertain, or code is deleted. Substitute `{{FAMILY}}=generalist`.

**No static checklist** — this family is pure **open-ended hunt**, graded for recall. The Checker reasons about what the change does and surfaces any logic error, correctness bug, security risk, or data hazard regardless of domain. The Cynic still refutes; the Researcher still tie-breaks.

**Why it exists:** routing on globs/signals is brittle (a bug can live in an unnamed file, or a PR can delete a guard). The generalist guarantees no PR passes with zero families awake — "when unsure, wake everything." (BUILD_PLAN §7.1.)
