#!/usr/bin/env bash
# Sandbox test for cc-sessions: synthetic transcripts in a temp dir (--root), so it
# never reads your real ~/.claude/projects.
#   tests/cc-sessions.sh                  test this checkout's script
#   TOOL=/path/to/cc-sessions tests/...   test another copy
set -uo pipefail
TOOL=${TOOL:-$(cd "$(dirname "$0")/.." && pwd)/skills/mining-claude-sessions/bin/cc-sessions}
T=$(mktemp -d /tmp/cc-sessions-test.XXXXXX)
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc, output was: $out"; fi; }
run() { out=$("$TOOL" "$@" --root "$T/projects" 2>&1); rc=$?; }

python3 - "$T/projects" <<'PY'
import json, os, sys
root = sys.argv[1]
def write(path, recs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for r in recs:
            f.write(json.dumps(r) + "\n")
A = "11111111-2222-3333-4444-555555555555"
B = "99999999-8888-7777-6666-555555555555"
write(f"{root}/-work-demo-proj/{A}.jsonl", [
    {"type": "ai-title", "aiTitle": "Rotate the widget cache"},
    {"type": "user", "cwd": "/work/demo/proj", "timestamp": "2026-11-01T10:00:00Z", "origin": {"kind": "human"},
     "message": {"content": "rotate the widget cache and check zorblax logs"}},
    {"type": "user", "timestamp": "2026-11-01T10:00:05Z", "origin": {"kind": "task-notification"},
     "message": {"content": "<task-notification>done</task-notification>"}},
    {"type": "assistant", "timestamp": "2026-11-01T10:01:00Z", "message": {"content": [
        {"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command":
            "printf '%s\\n' 'hunter2pass' | sudo -S systemctl restart widget && curl -H 'Authorization: Bearer abcdef123456789' https://x"}},
        {"type": "tool_use", "id": "t2", "name": "Edit", "input": {"file_path": "/work/demo/proj/cache.py"}},
        {"type": "tool_use", "id": "t3", "name": "Skill", "input": {"skill": "de-slopping"}},
        {"type": "tool_use", "id": "t4", "name": "mcp__linear__get_issue", "input": {"id": "X"}}]}},
    {"type": "user", "timestamp": "2026-11-01T10:01:05Z", "message": {"content": [
        {"type": "tool_result", "tool_use_id": "t1", "is_error": True, "content": "Exit code 1 SECRETVALUE42 failed"}]}},
    {"type": "pr-link", "prUrl": "https://github.com/o/r/pull/9", "prRepository": "o/r", "prNumber": 9,
     "timestamp": "2026-11-01T10:02:00Z"},
    {"type": "pr-link", "prUrl": "https://github.com/o/r/pull/9", "prRepository": "o/r", "prNumber": 9,
     "timestamp": "2026-11-01T10:03:00Z"},
    {"type": "user", "timestamp": "2026-11-01T10:04:00Z", "origin": {"kind": "human"}, "message": {"content": "keep going"}},
])
write(f"{root}/-work-demo-proj/{A}/subagents/agent-a.jsonl", [
    {"type": "assistant", "timestamp": "2026-11-01T10:05:00Z", "message": {"content": [
        {"type": "tool_use", "id": "u1", "name": "Bash", "input": {"command": "git status"}}]}}])
C = "33333333-4444-5555-6666-777777777777"
long_cmd = "echo start " + "y" * 600 + " needlecmd"
long_prompt = "q" * 3500 + " needleprompt"
write(f"{root}/-work-PrivateClient-x/{C}.jsonl", [
    {"type": "ai-title", "aiTitle": "Quarterly sync"},
    {"type": "user", "cwd": "/work/PrivateClient/x y", "timestamp": "2026-11-03T09:00:00Z", "origin": {"kind": "human"},
     "message": {"content": "echo orchidpetal | sudo -S true"}},
    {"type": "user", "timestamp": "2026-11-03T09:01:00Z", "origin": {"kind": "human"},
     "message": {"content": "echo orchidpetal | sudo -S true"}},
    {"type": "user", "timestamp": "2026-11-03T09:02:00Z", "origin": {"kind": "human"},
     "message": {"content": "x" * 280 + " echo edgepass77 | sudo -S true"}},
    {"type": "user", "timestamp": "2026-11-03T09:03:00Z", "origin": {"kind": "human"}, "message": {"content": long_prompt}},
    {"type": "assistant", "timestamp": "2026-11-03T09:04:00Z", "message": {"content": [
        {"type": "tool_use", "id": "c1", "name": "Bash", "input": {"command":
            "curl -H 'Cookie: session=cookieone; refresh=cookietwo' https://x && sshpass -v -p sshpwd99 ssh h && echo kspw | sudo -kS true"}},
        {"type": "tool_use", "id": "c2", "name": "Bash", "input": {"command": "sudo -u postgres psql -c 'select 1'"}},
        {"type": "tool_use", "id": "c3", "name": "Bash", "input": {"command": "if test -f foo; then git status; fi"}},
        {"type": "tool_use", "id": "c4", "name": "Bash", "input": {"command": long_cmd}}]}},
])
write(f"{root}/-work-demo-other/{B}.jsonl", [
    {"type": "ai-title", "aiTitle": "Zorblax dashboard"},
    {"type": "user", "cwd": "/work/demo/other", "timestamp": "2026-11-02T09:00:00Z", "origin": {"kind": "human"},
     "message": {"content": "build the zorblax dashboard, zorblax panels first"}},
    {"type": "user", "timestamp": "2026-11-02T09:10:00Z", "origin": {"kind": "human"}, "message": {"content": "keep going"}},
])
PY
printf '# values to mask\nSECRETVALUE42\nPrivateClient\n' > "$T/mask"

run find zorblax
check "find ranks the session whose title matches first" '[ $rc -eq 0 ] && [[ "$(echo "$out" | head -1)" == *"Zorblax dashboard"* ]]'
check "find prints a resume command with the cwd" '[[ $out == *"cd -- /work/demo/proj && claude --resume 11111111-2222-3333-4444-555555555555"* ]]'
run find zorblax widget
check "find needs every word: only one session has both" '[ $rc -eq 0 ] && [[ $out == *"widget"* ]] && [[ $out != *"dashboard"* ]]'
run find nothingmatches
check "no match exits 1" '[ $rc -eq 1 ]'
run find zorblax --project other
check "--project narrows the search" '[[ $out == *"dashboard"* ]] && [[ $out != *"widget cache"* ]]'

run show 1111 --mask-file "$T/mask"
check "show counts typed prompts only, not task notifications" '[[ $out == *"2 typed prompts"* ]]'
check "show lists the PR once" '[ "$(echo "$out" | grep -c "pull/9")" -eq 1 ]'
check "show counts the subagent and the tool error" '[[ $out == *"1 subagents"* ]] && [[ $out == *"1 tool errors"* ]]'
check "show lists commands, skills, MCP servers and edited files" '[[ $out == *"systemctl 1"* ]] && [[ $out == *"de-slopping 1"* ]] && [[ $out == *"mcp__linear 1"* ]] && [[ $out == *"/work/demo/proj/cache.py"* ]]'
run show 3333 --mask-file "$T/mask"
check "show masks a value inside the working directory" '[[ $out != *PrivateClient* ]]'
check "show masks a password just before the display cut" '[[ $out != *edgepass77* ]]'
check "the resume command quotes a directory with a space" '[[ $out == *"cd -- '"'"'/work/<masked>/x y'"'"' && claude --resume"* ]]'
run find needlecmd
check "find matches past the first 500 characters of a command" '[ $rc -eq 0 ] && [[ $out == *"Quarterly sync"* ]]'
run find needleprompt
check "find matches past the first 3,000 characters of a prompt" '[ $rc -eq 0 ] && [[ $out == *"Quarterly sync"* ]]'
run show abc
check "an unknown prefix is an error" '[ $rc -ne 0 ] && [[ $out == *"no session id starts with"* ]]'

run stats --mask-file "$T/mask"
check "stats counts sessions, subagents and prompts" '[[ $out == *"3 sessions, 1 subagent transcripts, 8 typed prompts"* ]]'
check "stats never prints a sudo -S password from repeated prompts" '[[ $out != *orchidpetal* ]]'
check "stats parses sudo -u and if/then: psql and git, not postgres" '[[ $out == *"psql"* ]] && [[ $out == *"git 1"* || $out == *"git 2"* ]] && [[ $out != *"postgres 1"* ]]'
check "a mask-file value is masked in every stats line" '[[ $out != *PrivateClient* ]]'
check "stats lists repeated short prompts with session counts" '[[ $out == *"2   2  keep going"* ]]'
run stats --json
check "stats --json is valid JSON" 'echo "$out" | python3 -c "import json,sys; json.load(sys.stdin)"'
run stats --no-subagents
check "--no-subagents leaves the subagent out" '[[ $out == *"0 subagent transcripts"* ]]'

run export "$T/ev.jsonl" --mask-file "$T/mask"
check "export writes mode 600" '[ "$(stat -c %a "$T/ev.jsonl" 2>/dev/null || stat -f %Lp "$T/ev.jsonl")" = 600 ]'
check "export masks the sudo -S password, the bearer token and the mask-file value" '! grep -q -E "hunter2pass|abcdef123456789|SECRETVALUE42" "$T/ev.jsonl"'
check "export masks whole Cookie headers, sshpass -v -p and sudo -kS" '! grep -q -E "cookieone|cookietwo|sshpwd99|kspw" "$T/ev.jsonl"'
check "export masks paths and directories too" '! grep -q PrivateClient "$T/ev.jsonl"'
run export "$T/ev.jsonl"
check "export refuses an existing file" '[ $rc -ne 0 ] && [[ $out == *"already exists"* ]]'
ln -s "$T/projects/-work-demo-proj/11111111-2222-3333-4444-555555555555.jsonl" "$T/link.jsonl"
run export "$T/link.jsonl"
check "export refuses a symlink, so a transcript cannot be overwritten" '[ $rc -ne 0 ] && [ -s "$T/projects/-work-demo-proj/11111111-2222-3333-4444-555555555555.jsonl" ]'
check "export keeps the rest of the command" 'grep -q "sudo -S systemctl restart widget" "$T/ev.jsonl"'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
