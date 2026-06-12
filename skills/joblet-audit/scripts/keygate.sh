#!/usr/bin/env bash
# keygate.sh — gate for the privileged commands (/35398 /46408 → approver; /456098 → source).
# The skill stores only a SHA-256 hash of each key in .joblet-audit/config.json — never the key itself.
#
#   keygate.sh set    <approver|source> <key>   # one-time: store the hash (run by the key holder)
#   keygate.sh verify <approver|source> <key>   # exit 0 if key matches stored hash, else exit 1
#   keygate.sh status                           # show which keys are set (hashes present) + rotation age
#
# The command handlers call `verify` before doing anything privileged.
set -euo pipefail
CFG="${JOBLET_AUDIT_CONFIG:-.joblet-audit/config.json}"
NODE="${NODE_BIN:-node}"

hash_of() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }   # macOS/Linux; falls back below
if ! command -v shasum >/dev/null 2>&1; then hash_of(){ printf '%s' "$1" | sha256sum | cut -d' ' -f1; }; fi

field_for() { case "$1" in approver) echo approver_key_sha256;; source) echo source_key_sha256;; *) echo "role must be 'approver' or 'source'" >&2; exit 2;; esac; }

cmd="${1:-}"
case "$cmd" in
  set)
    role="${2:?role}"; key="${3:?key}"; f="$(field_for "$role")"; h="$(hash_of "$key")"
    "$NODE" -e "const fs=require('fs');const p=process.argv[1];const c=JSON.parse(fs.readFileSync(p,'utf8'));c.keys=c.keys||{};c.keys['$f']='$h';fs.writeFileSync(p,JSON.stringify(c,null,2)+'\n');" "$CFG"
    echo "stored $role key hash in $CFG (the key itself was not saved)";;
  verify)
    role="${2:?role}"; key="${3:?key}"; f="$(field_for "$role")"
    want="$("$NODE" -e "const c=require('$PWD/$CFG');process.stdout.write((c.keys&&c.keys['$f'])||'')")"
    case "$want" in ""|"<set-by"*) echo "DENY: $role key not configured yet (run: keygate.sh set $role <key>)" >&2; exit 1;; esac
    if [ "$(hash_of "$key")" = "$want" ]; then echo "OK: $role key valid"; exit 0
    else echo "DENY: $role key invalid" >&2; exit 1; fi;;
  status)
    "$NODE" -e "const c=require('$PWD/$CFG');const k=c.keys||{};const set=v=>v&&!String(v).startsWith('<set-by')?'SET':'not set';console.log('approver:',set(k.approver_key_sha256));console.log('source  :',set(k.source_key_sha256));console.log('token rotation:',JSON.stringify(k.provider_tokens||{}));";;
  *) echo "usage: keygate.sh [set|verify|status] <approver|source> <key>" >&2; exit 2;;
esac
