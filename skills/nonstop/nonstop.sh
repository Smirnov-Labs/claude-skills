#!/bin/bash
# nonstop.sh — Session-scoped Stop hook for nonstop mode.
#
# Each session has its own flag file, ~/.claude/hooks/state/nonstop-<session_id>.active.
# The skill creates it with the ID that Claude Code puts in CLAUDE_CODE_SESSION_ID, and
# removes it to turn nonstop mode off. This hook reads session_id from its JSON input,
# so it looks only at the flag of the session that is stopping.
#
# Fork change (see UPSTREAM): upstream turned nonstop on and off through shared
# nonstop.activate and nonstop.deactivate files, and the next session to stop took
# them, so one session could take another session's activation. This hook ignores them.

STATE_DIR="$HOME/.claude/hooks/state"
NONSTOP_MAX="${NONSTOP_MAX:-5}"  # max nudges before auto-deactivation; 0 = unlimited

# --- Read hook input from stdin ---
input=$(cat)

# --- Read session_id and stop_hook_active from the JSON input ---
# Python checks the session ID before the shell sees it: letters, digits, - and _ only,
# because the ID goes into a file name. The shell reads the result without eval.
# -I -S: the hook runs in the session's directory and environment, so Python must not
# import modules from there or run startup code (.pth, sitecustomize) from a virtualenv.
fields=$(printf '%s' "$input" | python3 -I -S -c "
import json, re, sys
d = json.load(sys.stdin)
sid = d.get('session_id')
if not isinstance(sid, str) or not re.fullmatch(r'[A-Za-z0-9_-]+', sid):
    sys.exit(1)
print(sid, 'true' if str(d.get('stop_hook_active', False)).lower() == 'true' else 'false')
" 2>/dev/null) || exit 0
read -r session_id stop_hook_active <<< "$fields"

active_file="$STATE_DIR/nonstop-${session_id}.active"
counter_file="$STATE_DIR/nonstop-${session_id}.count"

# --- Check if nonstop mode is active for THIS session ---
[ -f "$active_file" ] || exit 0

# --- If already nudged once this turn, allow stop (prevent infinite loop) ---
[ "$stop_hook_active" = "true" ] && exit 0

# --- Counter: track nudges, bail after NONSTOP_MAX ---
count=0
[ -f "$counter_file" ] && count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"

if [ "$NONSTOP_MAX" -gt 0 ] && [ "$count" -gt "$NONSTOP_MAX" ]; then
  rm -f "$active_file" "$counter_file"
  exit 0
fi

# --- Block and nudge with decision framework ---
cat <<EOF
{"decision":"block","reason":"[nonstop mode — nudge] Do NOT stop. Follow the nonstop protocol:\n\n1. CHECK TASKS: Review your task list. Is every task completed?\n2. IF BLOCKED on something:\n   a. Can you solve it yourself? (search code, read docs, fix errors) → Do it.\n   b. Can you work around it WITHOUT changing the outcome? → Do it, update the task with what you did.\n   c. Is it a HIGH-RISK op not pre-approved? → Mark task as blocked, move to next task.\n   d. Truly stuck on everything? → Deactivate nonstop: rm -f ~/.claude/hooks/state/nonstop-${session_id}.active ~/.claude/hooks/state/nonstop-${session_id}.count\n3. FOR LONG-RUNNING OPS: Spawn a background Agent, don't block.\n4. NEVER: brute-force retry, disable safety checks, guess credentials, or take destructive actions not pre-approved.\n\nKeep working."}
EOF
