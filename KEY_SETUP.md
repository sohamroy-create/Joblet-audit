# Key setup — one-time (closes flag 0.5)

The privileged commands are gated by a SHA-256 hash stored in `.joblet-audit/config.json`. The **secret keys themselves are never stored** — only their hashes. Setting them is a one-liner run by the key holder; the key never leaves their machine.

## Who sets what
| Key | Gates | Held by |
|---|---|---|
| **approver** | `/35398` (apply updates), `/46408` (rotate tokens) | the reviewer(s) |
| **source** | `/456098` (change agent logic/source) | **Soham** only |

## Set a key (run locally, once)
```bash
cd <repo root>           # where .joblet-audit/ lives
export NODE_BIN=$(command -v node)
# choose a strong secret and store ONLY its hash:
bash scripts/keygate.sh set approver "YOUR-APPROVER-SECRET"
bash scripts/keygate.sh set source   "SOHAMS-SOURCE-SECRET"     # Soham runs this one
```
Then commit the updated `config.json` (it now holds the hash, not the key) to the `joblet-audit-corpus` branch so all installs share the same gate.

## How a command checks it (already wired)
Each privileged command runs, before doing anything:
```bash
bash scripts/keygate.sh verify approver "<key the user supplied>"   # exit 0 = allow, 1 = deny
```
- Wrong key → `DENY: ... invalid` (no side effects).
- Key not set yet → `DENY: ... not configured`.
- `/456098` denial message tells the user: *"ask Soham."*

## Check state anytime
```bash
bash scripts/keygate.sh status      # shows which keys are SET + token rotation ages
```

## Notes (honest)
- This is a **shared-secret gate**, not password-grade crypto. The real control is *who holds the key* + *who has write access to this repo*. A bare SHA-256 is sufficient for that purpose.
- Rotate a key by simply running `set` again with a new secret.
- Token (Vercel/Supabase/GitHub) rotation is separate — see `/46408` and the 15-day `provider_tokens` fields in `config.json`.
