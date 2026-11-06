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
D = "44444444-5555-6666-7777-888888888888"
write(f"{root}/-work-demo-r2/{D}.jsonl", [
    {"type": "ai-title", "aiTitle": "Round two"},
    {"type": "user", "cwd": "/work/demo/quote'side", "timestamp": "2026-11-04T09:00:00Z", "origin": {"kind": "human"},
     "message": {"content": "start"}},
    {"type": "user", "timestamp": "2026-11-04T09:00:10Z", "origin": {"kind": "human"},
     "message": {"content": "Cookie: session=abc; refresh=def"}},
    {"type": "user", "timestamp": "2026-11-04T09:00:20Z", "origin": {"kind": "human"},
     "message": {"content": "Cookie: session=abc; refresh=def"}},
    {"type": "assistant", "timestamp": "2026-11-04T09:01:00Z", "message": {"content": [
        {"type": "tool_use", "id": "d1", "name": "Bash", "input": {"command": "echo pathpw11 | /usr/bin/sudo -S true"}},
        {"type": "tool_use", "id": "d2", "name": "Bash", "input": {"command": "echo \"rose|tulipkey\" | sudo -S true"}},
        {"type": "tool_use", "id": "d3", "name": "Bash", "input": {"command": "password=\"correct horse battery staple\" ./run"}},
        {"type": "tool_use", "id": "d4", "name": "Bash", "input": {"command": "curl -H 'Cookie: session=\"quotedck1\"; refresh=quotedck2' https://x"}},
        {"type": "tool_use", "id": "d5", "name": "Bash", "input": {"command": "printf '%s\\n' 'rose; fragpw33 berry' | sudo -S true"}},
        {"type": "tool_use", "id": "d6", "name": "Bash", "input": {"command": "psql -c 'SELECT 1; DROP TABLE example;'"}},
        {"type": "tool_use", "id": "d7", "name": "Bash", "input": {"command": "sudo --user postgres psql; sudo -Hu postgres psql"}},
        {"type": "tool_use", "id": "d8", "name": "Bash", "input": {"command": "timeout --signal TERM 10 git status; timeout -s TERM 10 git status"}},
        {"type": "tool_use", "id": "e1", "name": "Bash", "input": {"command": "printf '%s' '|' 'qpipepw77' | sudo -S true"}},
        {"type": "tool_use", "id": "e2", "name": "Bash", "input": {"command": "grep '|' notes.txt"}},
        {"type": "tool_use", "id": "e3", "name": "Bash", "input": {"command": "# Check repository\ngit status\npytest -q"}},
        {"type": "tool_use", "id": "e4", "name": "Bash", "input": {"command": "git log # inline note\nmake test"}},
        {"type": "tool_use", "id": "f1", "name": "Bash", "input": {"command": "psql 'postgresql://alice:urlpw551@db.example/app'"}},
        {"type": "tool_use", "id": "f2", "name": "Bash", "input": {"command": "curl -u alice:curlpw552 https://example.test"}},
        {"type": "tool_use", "id": "f3", "name": "Bash", "input": {"command": "LABEL='hello world' rustc --version"}},
        {"type": "tool_use", "id": "f4", "name": "Bash", "input": {"command": "curl --data='a|zzfake; yyfake' https://example.test"}},
        {"type": "tool_use", "id": "f5", "name": "Bash", "input": {"command": "curl -H 'Cookie: session=ck553; refresh=ck554' https://keepme.example && cargo build"}},
        {"type": "tool_use", "id": "f6", "name": "mcp__x__z", "input": {"headers": {"Cookie": ["session=listck555"]}}},
        {"type": "tool_use", "id": "g1", "name": "Bash", "input": {"command": "curl -ualice:attpw661 https://example.test"}},
        {"type": "tool_use", "id": "g2", "name": "Bash", "input": {"command": "curl \\\n  -u alice:contpw662 https://example.test"}},
        {"type": "tool_use", "id": "g3", "name": "Bash", "input": {"command": "curl -b 'session=bck663; refresh=bck664' https://example.test"}},
        {"type": "tool_use", "id": "g4", "name": "Bash", "input": {"command": "echo checking; jq --version; echo sudopw665 | sudo -S systemctl restart nginx"}},
        {"type": "tool_use", "id": "g5", "name": "Bash", "input": {"command": "sudo \\\n  apt-get update"}},
        {"type": "tool_use", "id": "d9", "name": "mcp__x__y", "input": {"Cookie": "session=mcpck1; refresh=mcpck2", "q": "private\"client Caf\u00e9"}}]}},
])
write(f"{root}/-work-demo-other/{B}.jsonl", [
    {"type": "ai-title", "aiTitle": "Zorblax dashboard"},
    {"type": "user", "cwd": "/work/demo/other", "timestamp": "2026-11-02T09:00:00Z", "origin": {"kind": "human"},
     "message": {"content": "build the zorblax dashboard, zorblax panels first"}},
    {"type": "user", "timestamp": "2026-11-02T09:10:00Z", "origin": {"kind": "human"}, "message": {"content": "keep going"}},
])
PY
printf '# values to mask\nSECRETVALUE42\nPrivateClient\nprivate"client\nCaf\xc3\xa9\nquote'"'"'side\n' > "$T/mask"

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
run show 4444 --mask-file "$T/mask"
check "a password inside quotes never shows up as a command" '[[ $out != *fragpw33* ]]'
check "SQL inside quotes is not a command" '[[ $out != *"DROP"* ]]'
check "a quoted pipe never turns a password into a command" '[[ $out != *qpipepw77* ]]'
check "a quoted pipe invents no command" '[[ $out != *"notes.txt"* ]]'
check "comments do not swallow the lines after them" '[[ $out == *"pytest 1"* ]] && [[ $out == *"make 1"* ]]'
check "an assignment with a quoted space still finds the command" '[[ $out == *"rustc 1"* ]]'
check "quotes inside an option value invent no command" '[[ $out != *zzfake* ]] && [[ $out != *yyfake* ]]'
check "a Cookie header does not hide the commands after it" '[[ $out == *"cargo 1"* ]]'
check "a sudo -S password does not hide the commands before it" '[[ $out == *"jq 1"* ]]'
check "a line continuation keeps the command countable" '[[ $out == *"apt-get 1"* ]]'
check "wrapper long options and clusters: psql and git, not postgres or TERM" '[[ $out == *"psql "* ]] && [[ $out == *"git "* ]] && [[ $out != *postgres* ]] && [[ $out != *TERM* ]]'
check "a masked literal in the directory stays masked in the resume command" '[[ $out != *"quote"*"side"* ]]'
run find PrivateClient --mask-file "$T/mask"
check "a failed search does not echo a masked word" '[[ $out != *rivate* ]]'
out=$("$TOOL" stats --days sk-abcdefgh12345678 --root "$T/projects" 2>&1); rc=$?
check "a startup error is masked" '[ $rc -ne 0 ] && [[ $out != *abcdefgh12345678* ]]'
out=$("$TOOL" stats --root "$T/PrivateClient-missing" --mask-file "$T/mask" 2>&1); rc=$?
check "a missing root is reported masked" '[ $rc -ne 0 ] && [[ $out != *PrivateClient* ]]'
run show abc
check "an unknown prefix is an error" '[ $rc -ne 0 ] && [[ $out == *"no session id starts with"* ]]'

run stats --mask-file "$T/mask"
check "stats counts sessions, subagents and prompts" '[[ $out == *"4 sessions, 1 subagent transcripts, 11 typed prompts"* ]]'
check "stats never prints a sudo -S password from repeated prompts" '[[ $out != *orchidpetal* ]]'
check "stats parses sudo -u and if/then: psql and git, not postgres" '[[ $out == *"psql "* ]] && [[ $out == *"git "* ]] && [[ $out != *"postgres "* ]]'
check "a mask-file value is masked in every stats line" '[[ $out != *PrivateClient* ]]'
check "stats lists repeated short prompts with session counts" '[[ $out == *"2   2  keep going"* ]]'
run stats --json
check "stats --json is valid JSON, even with repeated Cookie prompts" 'echo "$out" | python3 -c "import json,sys; json.load(sys.stdin)"'
check "stats --json never shows the cookie values" '[[ $out != *"refresh=def"* ]]'
run stats --no-subagents
check "--no-subagents leaves the subagent out" '[[ $out == *"0 subagent transcripts"* ]]'

run export "$T/ev.jsonl" --mask-file "$T/mask"
check "export writes mode 600" '[ "$(stat -c %a "$T/ev.jsonl" 2>/dev/null || stat -f %Lp "$T/ev.jsonl")" = 600 ]'
check "export masks the sudo -S password, the bearer token and the mask-file value" '! grep -q -E "hunter2pass|abcdef123456789|SECRETVALUE42" "$T/ev.jsonl"'
check "export masks whole Cookie headers, sshpass -v -p and sudo -kS" '! grep -q -E "cookieone|cookietwo|sshpwd99|kspw" "$T/ev.jsonl"'
check "export masks paths and directories too" '! grep -q PrivateClient "$T/ev.jsonl"'
check "export masks URL and curl -u credentials" '! grep -q -E "urlpw551|curlpw552" "$T/ev.jsonl"'
check "export masks -uUSER:PASS, -u after a continuation, and curl -b cookies" '! grep -q -E "attpw661|contpw662|bck663|bck664" "$T/ev.jsonl"'
check "export keeps the command before a sudo -S password" 'grep -q "echo checking; jq --version; echo <redacted>" "$T/ev.jsonl"'
check "export masks a Cookie value but keeps the rest of the command" '! grep -q -E "ck553|ck554" "$T/ev.jsonl" && grep -q "keepme.example && cargo build" "$T/ev.jsonl"'
check "export redacts list values under a sensitive key" '! grep -q listck555 "$T/ev.jsonl"'
check "export masks sudo by path, quoted pipes, quoted passwords and quoted cookies" '! grep -q -E "pathpw11|tulipkey|horse battery|quotedck1|quotedck2" "$T/ev.jsonl"'
check "export masks literals and cookies inside MCP inputs before JSON escaping" '! python3 -c "
import json,sys
raw=open(sys.argv[1]).read(); dec=json.dumps([json.loads(l) for l in raw.splitlines()], ensure_ascii=False)
bad=[s for s in [\"mcpck2\", \"private\\\"client\", \"Caf\u00e9\", \"Caf\\\\u00e9\"] if s in raw or s in dec or s in json.dumps(json.loads(dec))]
sys.exit(0 if bad else 1)" "$T/ev.jsonl"'
run export "$T/ev.jsonl"
check "export refuses an existing file" '[ $rc -ne 0 ] && [[ $out == *"already exists"* ]]'
ln -s "$T/projects/-work-demo-proj/11111111-2222-3333-4444-555555555555.jsonl" "$T/link.jsonl"
run export "$T/link.jsonl"
check "export refuses a symlink, so a transcript cannot be overwritten" '[ $rc -ne 0 ] && [ -s "$T/projects/-work-demo-proj/11111111-2222-3333-4444-555555555555.jsonl" ]'
check "export keeps the rest of the command" 'grep -q "sudo -S systemctl restart widget" "$T/ev.jsonl"'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
