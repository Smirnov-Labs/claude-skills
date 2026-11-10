#!/usr/bin/env bash
# Sandbox test for the nonstop Stop hook and the commands in its SKILL.md.
# Every check runs with a temporary HOME, so it never reads or writes your real
# ~/.claude/hooks/state. The turn-on and turn-off commands are the first and
# second bash blocks of SKILL.md, run as written with only the session ID set,
# so the skill's instructions are tested together with the hook.
#   tests/nonstop.sh                       test this checkout
#   HOOK=/path/to/nonstop.sh tests/...     test another copy of the hook
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK=${HOOK:-$ROOT/skills/nonstop/nonstop.sh}
SKILL=${SKILL:-$ROOT/skills/nonstop/SKILL.md}
T=$(mktemp -d /tmp/nonstop-test.XXXXXX)
S=$T/home/.claude/hooks/state
pass=0 fail=0 out="" rc=0 MAX=5
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc, stdout: $out"; echo "     state: $(ls -A "$S" 2>/dev/null | tr '\n' ' ')"; fi; }

cat > "$T/isblock.py" <<'EOF'
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if d.get("decision") == "block" and d.get("reason") else 1)
EOF

# stop ID [ACTIVE]: one Stop event for session ID, the JSON that Claude Code sends.
stop() { out=$(printf '{"session_id":"%s","stop_hook_active":%s}' "$1" "${2:-false}" | HOME=$T/home NONSTOP_MAX=$MAX bash "$HOOK" 2>/dev/null); rc=$?; }
blocked() { [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -I "$T/isblock.py" 2>/dev/null; }
allowed() { [ "$rc" -eq 0 ] && [ -z "$out" ]; }

# block N: the Nth bash block of SKILL.md, without its list indent.
block() { awk -v n="$1" '
  /^[[:space:]]*```bash[[:space:]]*$/ { if (++k == n) { inb = 1; next } }
  inb && /^[[:space:]]*```[[:space:]]*$/ { exit }
  inb { sub(/^[[:space:]]+/, ""); print }' "$SKILL"; }
# skill N ID [SHELL]: run block N the way session ID would, in bash or zsh.
skill() { HOME=$T/home CLAUDE_CODE_SESSION_ID=$2 "${3:-bash}" -c "$(block "$1")" >/dev/null 2>&1; rc=$?; out=""; }
reset() { rm -rf "${T:?}/home"; mkdir -p "$S"; }

nblocks=$(grep -cE '^[[:space:]]*```bash[[:space:]]*$' "$SKILL")
check "SKILL.md has two bash blocks: turn on, then turn off" '[ "$nblocks" -eq 2 ]'

reset; stop session-a
check "a session that did not turn nonstop on may stop" 'allowed'

reset; skill 1 session-a
stop session-b; check "turning nonstop on in one session does not block another" 'allowed'
stop session-a; check "the session that turned it on is blocked and nudged" 'blocked'
check "the nudge names that session's own flag, not a shared file" '[[ $out == *"nonstop-session-a.active"* ]] && [[ $out != *"nonstop.deactivate"* ]]'

reset; touch "$S/nonstop.activate"; stop session-b
check "a shared nonstop.activate file turns on no session" 'allowed'

reset; skill 1 session-a; skill 1 session-b; touch "$S/nonstop.deactivate"; stop session-b
check "a shared nonstop.deactivate file turns off no session" 'blocked'

reset; skill 1 session-a; skill 1 session-b; skill 2 session-a
stop session-a; check "turning nonstop off ends it for that session and removes its files" 'allowed && [ ! -e "$S/nonstop-session-a.active" ] && [ ! -e "$S/nonstop-session-a.count" ]'
stop session-b; check "turning nonstop off in one session leaves another on" 'blocked'

reset; HOME=$T/home env -u CLAUDE_CODE_SESSION_ID bash -c "$(block 1)" >/dev/null 2>&1; rc=$?; out=""
check "without CLAUDE_CODE_SESSION_ID the turn-on block fails and writes nothing" '[ "$rc" -ne 0 ] && [ -z "$(ls -A "$S")" ]'

reset; skill 1 session-a; stop session-a true
check "a second stop in the same turn is allowed (stop_hook_active)" 'allowed'

reset; skill 1 session-a; MAX=2
stop session-a; b1=$out; stop session-a; b2=$out; stop session-a; MAX=5
check "after NONSTOP_MAX nudges the session may stop and its files are gone" 'allowed && [[ $b1 == *block* && $b2 == *block* ]] && [ -z "$(ls -A "$S")" ]'

reset; stop "\$(touch $T/pwned)"
check "a session ID with shell syntax runs nothing and is ignored" 'allowed && [ ! -e "$T/pwned" ]'

if command -v zsh >/dev/null 2>&1; then
  reset; skill 1 session-a zsh; stop session-a; check "the turn-on block works in zsh" 'blocked'
  skill 2 session-a zsh; stop session-a; check "the turn-off block works in zsh" 'allowed'
else
  echo "skip zsh checks: zsh is not installed"
fi

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
