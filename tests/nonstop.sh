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
# nudgecmd.py: the turn-off command that the nudge tells the model to run.
cat > "$T/nudgecmd.py" <<'EOF'
import json, sys
for line in json.load(sys.stdin)["reason"].splitlines():
    if "Deactivate nonstop:" in line:
        print(line.split("Deactivate nonstop:", 1)[1].strip())
        break
EOF

# stop ID [ACTIVE]: one Stop event for session ID, the JSON that Claude Code sends,
# run in directory $CWD (default: here), as Claude Code runs the hook in the session's directory.
stop() { out=$(cd "${CWD:-.}" && printf '{"session_id":"%s","stop_hook_active":%s}' "$1" "${2:-false}" | HOME=$T/home NONSTOP_MAX=$MAX bash "$HOOK" 2>/dev/null); rc=$?; }
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

# twosessions SHELL: both sessions turn nonstop on and get one nudge, then A turns it off.
twosessions() {
  reset; skill 1 session-a "$1"; skill 1 session-b "$1"
  stop session-a; check "($1) the turn-on command blocks its own session" 'blocked'
  stop session-b
  skill 2 session-a "$1"; offrc=$rc; bcount=$(cat "$S/nonstop-session-b.count" 2>/dev/null)
  check "($1) the turn-off command removes the flag and count of its own session" '[ "$offrc" -eq 0 ] && [ ! -e "$S/nonstop-session-a.active" ] && [ ! -e "$S/nonstop-session-a.count" ]'
  check "($1) the turn-off command leaves the flag and count of the other session" '[ -e "$S/nonstop-session-b.active" ] && [ "$bcount" = 1 ]'
  stop session-a; check "($1) the session that turned it off may stop" 'allowed'
  stop session-b; check "($1) the other session is still blocked" 'blocked'
}
twosessions bash

reset; HOME=$T/home env -u CLAUDE_CODE_SESSION_ID bash -c "$(block 1)" >/dev/null 2>&1; rc=$?; out=""
check "without CLAUDE_CODE_SESSION_ID the turn-on block fails and writes nothing" '[ "$rc" -ne 0 ] && [ -z "$(ls -A "$S")" ]'

reset; skill 1 session-a; stop session-a true
check "a second stop in the same turn is allowed (stop_hook_active)" 'allowed'

reset; skill 1 session-a; MAX=2
stop session-a; b1=$out; stop session-a; b2=$out; stop session-a; MAX=5
check "after NONSTOP_MAX nudges the session may stop and its files are gone" 'allowed && [[ $b1 == *block* && $b2 == *block* ]] && [ -z "$(ls -A "$S")" ]'

reset; skill 1 session-a; skill 1 session-b; MAX=2
stop session-b; stop session-a; stop session-a; cmd=$(printf '%s' "$out" | python3 -I "$T/nudgecmd.py" 2>/dev/null)
HOME=$T/home bash -c "$cmd" >/dev/null 2>&1; cmdrc=$?; bcount=$(cat "$S/nonstop-session-b.count" 2>/dev/null)
check "the turn-off command in the nudge removes the flag and count of its session" '[ -n "$cmd" ] && [ "$cmdrc" -eq 0 ] && [ ! -e "$S/nonstop-session-a.active" ] && [ ! -e "$S/nonstop-session-a.count" ]'
check "the turn-off command in the nudge leaves the flag and count of the other session" '[ -e "$S/nonstop-session-b.active" ] && [ "$bcount" = 1 ]'
skill 1 session-a; stop session-a; b1=$out; stop session-a; MAX=5
check "turning nonstop on again after that gives the full budget of nudges" '[[ $b1 == *block* ]] && blocked'

reset; skill 1 session-a; skill 1 session-b; MAX=2
stop session-b; stop session-a; stop session-a; rm -f "$S/nonstop-session-a.active"
skill 1 session-a; bcount=$(cat "$S/nonstop-session-b.count" 2>/dev/null); stop session-a; MAX=5
check "turning nonstop on resets the nudge count of the session" 'blocked'
check "turning nonstop on leaves the flag and count of the other session" '[ -e "$S/nonstop-session-b.active" ] && [ "$bcount" = 1 ]'

# A json.py or shlex.py in the session's directory must not load when the hook runs there.
reset; mkdir -p "$T/repo"; skill 1 session-a
for m in json shlex; do printf 'open(%s, "w").write("ran")\n' "'$T/canary-$m'" > "$T/repo/$m.py"; done
CWD=$T/repo stop session-a
check "a json.py or shlex.py in the session's directory does not run, and the hook still works" 'blocked && [ ! -e "$T/canary-json" ] && [ ! -e "$T/canary-shlex" ]'

reset; stop "\$(touch $T/pwned)"
check "a session ID with shell syntax runs nothing and is ignored" 'allowed && [ ! -e "$T/pwned" ]'

reset; touch "$S/nonstop-bad.id.active"; stop bad.id
check "a session ID with a character outside A-Z a-z 0-9 _ - is ignored, even with a flag" 'allowed && [ ! -e "$S/nonstop-bad.id.count" ]'

if command -v zsh >/dev/null 2>&1; then
  twosessions zsh
else
  echo "skip zsh checks: zsh is not installed"
fi

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
