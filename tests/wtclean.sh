#!/usr/bin/env bash
# Sandbox test for wtclean: real git repos and worktrees under a temp dir, with a fake `gh`, a fake `git` that logs
# its calls and a fake Orca CLI on PATH, so it never reaches GitHub or a real Orca and never touches your checkouts.
# The fakes are Python, so they also run under run_bare's PATH, which holds only git, python3 and env.
#   tests/wtclean.sh                  test this checkout's script
#   TOOL=/path/to/wtclean tests/...   test another copy
set -uo pipefail
TOOL=${TOOL:-$(cd "$(dirname "$0")/.." && pwd)/skills/cleaning-merged-worktrees/bin/wtclean}
T=$(mktemp -d /tmp/wtclean-test.XXXXXX) || exit 1
REAL_GIT=$(command -v git)   # recorded before PATH changes: the fake git and the harness both run this one
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1
export HOME=$T/home FAKE=$T/fake REAL_GIT ORCA_CLI_COMMAND=$T/bin/orca
unset ORCA_USER_DATA_PATH
pass=0 fail=0 out="" rc=0 M="" W="" H="" WD=$T
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc, output was: $out"; fi; }

git() { "$REAL_GIT" "$@"; }   # the harness's own git calls skip the logging fake, so git.log shows only wtclean's calls
run() { : > "$FAKE/git.log"; out=$(cd "$WD" && "$TOOL" "$@" 2>&1); rc=$?; }
# like run, but no Orca CLI is reachable: ORCA_CLI_COMMAND is unset and PATH holds only the fakes plus git, python3, env
run_bare() { : > "$FAKE/git.log"; out=$(cd "$WD" && env -u ORCA_CLI_COMMAND PATH="$T/bin:$T/sysbin" "$TOOL" "$@" 2>&1); rc=$?; }
last() { printf '%s\n' "$out" | tail -n 1; }

mkdir -p "$T/bin" "$T/sysbin"
for tool in git python3 env; do ln -s "$(command -v "$tool")" "$T/sysbin/$tool"; done

cat > "$T/bin/git" <<'EOF'
#!/usr/bin/env python3
# Fake git: logs its arguments to $FAKE/git.log, then runs the real git.
# FAKE_GIT_REMOVE_FAIL=1 makes `worktree remove` print "fatal: refused" and exit 128 instead.
import os
import sys

args = sys.argv[1:]
with open(os.path.join(os.environ["FAKE"], "git.log"), "a") as log:
    log.write(" ".join(args) + "\n")
if os.environ.get("FAKE_GIT_REMOVE_FAIL") and any(a == "worktree" and b == "remove" for a, b in zip(args, args[1:])):
    print("fatal: refused", file=sys.stderr)
    sys.exit(128)
os.execv(os.environ["REAL_GIT"], [os.environ["REAL_GIT"]] + args)
EOF

cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env python3
# Fake gh: logs its arguments to $FAKE/gh.log. `pr list -R o/r --head B` prints $FAKE/prs/<B, / as __>.json or [].
# `api repos/o/r/compare/A...B` is answered from the bare origin ($FAKE_ORIGIN). FAKE_GH_FAIL=1 plays a 502 and
# FAKE_GH_GARBAGE=1 an HTML page. Anything else exits 9.
import os
import subprocess
import sys

args = sys.argv[1:]
fake = os.environ["FAKE"]
with open(os.path.join(fake, "gh.log"), "a") as log:
    log.write(" ".join(args) + "\n")
if os.environ.get("FAKE_GH_FAIL"):
    print("HTTP 502", file=sys.stderr)
    sys.exit(1)
if os.environ.get("FAKE_GH_GARBAGE"):
    print("<html>")
    sys.exit(0)


def flag(name):
    return args[args.index(name) + 1] if name in args[:-1] else None


def origin_git(*a):
    cmd = [os.environ["REAL_GIT"], "-C", os.environ["FAKE_ORIGIN"], *a]
    return subprocess.run(cmd, capture_output=True).returncode


if args[:2] == ["pr", "list"] and flag("-R") == "o/r" and flag("--head"):
    prs = os.path.join(fake, "prs", flag("--head").replace("/", "__") + ".json")
    sys.stdout.write(open(prs).read() if os.path.exists(prs) else "[]\n")
    sys.exit(0)
if args[:1] == ["api"] and args[1:2] and args[1].startswith("repos/o/r/compare/"):
    base, _, head = args[1][len("repos/o/r/compare/"):].partition("...")
    if origin_git("cat-file", "-e", base + "^{commit}") != 0:
        print("gh: Not Found (HTTP 404)", file=sys.stderr)
        sys.exit(1)
    if origin_git("merge-base", "--is-ancestor", base, head) == 0:
        print('{"status":"ahead","behind_by":0}')
    else:
        print('{"status":"diverged","behind_by":1}')
    sys.exit(0)
print("fake gh: unexpected: " + " ".join(args), file=sys.stderr)
sys.exit(9)
EOF

cat > "$T/bin/orca" <<'EOF'
#!/usr/bin/env python3
# Fake Orca CLI: logs its arguments to $FAKE/orca.log and answers from files in $FAKE. Any --force, and any command it
# does not know, exits 9. FAKE_ORCA_FAIL=1: every call says Orca is not running. FAKE_ORCA_RM_FAIL=1: `worktree rm`
# refuses. FAKE_ORCA_DELETES_BRANCH=1: `worktree rm` also deletes the worktree's branch. FAKE_PS2_TOUCH=FILE: from its
# second call on, `worktree ps` creates FILE before it answers.
import json
import os
import subprocess
import sys

args = sys.argv[1:]
fake = os.environ["FAKE"]
with open(os.path.join(fake, "orca.log"), "a") as log:
    log.write(" ".join(args) + "\n")


def reply(obj, code=0):
    print(json.dumps(obj))
    sys.exit(code)


def git(*a):
    return subprocess.run([os.environ["REAL_GIT"], *a], capture_output=True, text=True)


if os.environ.get("FAKE_ORCA_FAIL"):
    reply({"ok": False, "error": {"code": "runtime_unavailable", "message": "Orca is not running"}}, 1)
if "--force" in args:
    sys.exit(9)
if args[:2] == ["repo", "list"]:
    sys.stdout.write(open(os.path.join(fake, "repos.json")).read())
    sys.exit(0)
if args[:2] == ["worktree", "ps"]:
    with open(os.path.join(fake, "ps.count"), "a") as count:
        count.write("x\n")
    if len(open(os.path.join(fake, "ps.count")).read().splitlines()) >= 2 and os.environ.get("FAKE_PS2_TOUCH"):
        open(os.environ["FAKE_PS2_TOUCH"], "a").close()
    sys.stdout.write(open(os.path.join(fake, "ps.json")).read())
    sys.exit(0)
if args[:2] == ["worktree", "rm"] and "--worktree" in args[:-1] and args[args.index("--worktree") + 1].startswith("id:R1::"):
    wt = args[args.index("--worktree") + 1][len("id:R1::"):]
    refused = {"ok": False, "error": {"message": "refused"}}
    listing = git("-C", wt, "worktree", "list", "--porcelain").stdout.splitlines()
    if os.environ.get("FAKE_ORCA_RM_FAIL") or not listing:
        reply(refused, 1)
    main = listing[0][len("worktree "):]
    branch = git("-C", wt, "symbolic-ref", "--quiet", "--short", "HEAD").stdout.strip()
    if git("-C", main, "worktree", "remove", wt).returncode != 0:
        reply(refused, 1)
    if os.environ.get("FAKE_ORCA_DELETES_BRANCH") and branch:
        git("-C", main, "update-ref", "-d", "refs/heads/" + branch)
    reply({"ok": True, "result": {"removed": True}})
print("fake orca: unexpected: " + " ".join(args), file=sys.stderr)
sys.exit(9)
EOF
chmod +x "$T/bin/git" "$T/bin/gh" "$T/bin/orca"
export PATH="$T/bin:$PATH"

# A bare origin (reached as https://github.com/o/r.git through insteadOf) and a main checkout $M on main with one pushed
# commit. The fake Orca lists $M as its only repo and has no worktree rows.
setup() {
  rm -rf "${T:?}/home" "${FAKE:?}" "${T:?}/r"; mkdir -p "$T/home" "$FAKE" "$T/r"
  O=$T/r/origin.git; git init -q --bare -b main "$O"; export FAKE_ORIGIN=$O
  git config --file "$GIT_CONFIG_GLOBAL" url."$O".insteadOf "https://github.com/o/r.git"
  M=$T/r/main; git init -q -b main "$M"; git -C "$M" remote add origin https://github.com/o/r.git
  echo base > "$M/a.txt"; printf '.env\nnode_modules/\n' > "$M/.gitignore"; git -C "$M" add -A
  git -C "$M" commit -qm base; git -C "$M" push -q -u origin main
  printf '{"ok":true,"result":{"repos":[{"id":"R1","path":"%s","kind":"git"}]}}\n' "$M" > "$FAKE/repos.json"
  printf '{"ok":true,"result":{"worktrees":[],"totalCount":0,"truncated":false,"hostScope":{"hostIds":["local"]}}}\n' > "$FAKE/ps.json"
  WD=$M
}
# age PATH: make the worktree's git index and HEAD log look 48 hours old, so the 24-hour check passes
age() {
  local n p
  for n in index logs/HEAD; do
    p=$(git -C "$1" rev-parse --path-format=absolute --git-path "$n")
    if [ -e "$p" ]; then touch -d '48 hours ago' "$p"; fi
  done
}
# mkwt NAME BRANCH: worktree $W=$T/r/NAME of $M on a new BRANCH from origin/main, one pushed commit; H is its HEAD
mkwt() {
  W=$T/r/$1
  git -C "$M" worktree add -q -b "$2" "$W" origin/main
  echo "$2" >> "$W/a.txt"; git -C "$W" commit -qam "work on $2"; git -C "$W" push -q -u origin "$2"
  H=$(git -C "$W" rev-parse HEAD); age "$W"
}
# pr BRANCH STATE [HEAD] [CROSS]: add a pull request to what the fake gh lists for BRANCH (HEAD defaults to the branch tip)
pr() {
  local head=${3:-}
  [ -n "$head" ] || head=$(git -C "$M" rev-parse "refs/heads/$1")
  mkdir -p "$FAKE/prs"
  python3 - "$FAKE/prs/${1//\//__}.json" "$2" "$head" "${4:-false}" <<'PY'
import json
import os
import sys

f, state, head, cross = sys.argv[1:5]
prs = json.load(open(f)) if os.path.exists(f) else []
n = len(prs) + 1
prs.append({"number": n, "state": state, "headRefOid": head, "isCrossRepository": cross == "true",
            "url": "https://github.com/o/r/pull/%d" % n,
            "mergedAt": "2026-11-%02dT00:00:00Z" % n if state == "MERGED" else None})
with open(f, "w") as out:
    json.dump(prs, out)
PY
}
# orca_repo PATH KIND: add a repository to the fake `repo list` answer
orca_repo() {
  python3 - "$FAKE/repos.json" "$1" "$2" <<'PY'
import json
import sys

f, repo_path, kind = sys.argv[1:4]
d = json.load(open(f))
d["result"]["repos"].append({"id": "R%d" % (len(d["result"]["repos"]) + 1), "path": repo_path, "kind": kind})
with open(f, "w") as out:
    json.dump(d, out)
PY
}
# orca_row PATH [agents=N] [state=S] [live=N] [unverifiable=N] [attached=1] [children=ID,...] [id=ID]:
# add a worktree row to the fake `worktree ps` answer
orca_row() {
  local p=$1; shift
  python3 - "$FAKE/ps.json" "$p" "$@" <<'PY'
import json
import sys

f, row_path = sys.argv[1:3]
kw = dict(a.split("=", 1) for a in sys.argv[3:])
d = json.load(open(f))
d["result"]["worktrees"].append({
    "worktreeId": kw.get("id") or "R1::" + row_path, "path": row_path,
    "agents": [{"state": kw.get("state", "working")} for _ in range(int(kw.get("agents", 0)))],
    "liveTerminalCount": int(kw.get("live", 0)), "unverifiableTerminalCount": int(kw.get("unverifiable", 0)),
    "hasAttachedPty": kw.get("attached") == "1",
    "childWorktreeIds": [c for c in kw.get("children", "").split(",") if c], "isMainWorktree": False})
d["result"]["totalCount"] += 1
with open(f, "w") as out:
    json.dump(d, out)
PY
}
# orca_ps_patch STMT: run the Python statement STMT on the fake `worktree ps` answer, which it sees as d
orca_ps_patch() {
  python3 - "$FAKE/ps.json" "$1" <<'PY'
import json
import sys

f, stmt = sys.argv[1:3]
d = json.load(open(f))
exec(stmt)
with open(f, "w") as out:
    json.dump(d, out)
PY
}

# ---- tests ----
setup; run --apply --check
check "--apply with --check is a usage error" '[ $rc -eq 3 ]'
setup; run --bogus
check "an unknown flag is a usage error" '[ $rc -eq 3 ]'
setup; run --repo "$T/nowhere"
check "a --repo that is not a git repository is a usage error" '[ $rc -eq 3 ]'
setup; mkwt wt-a feat/a; pr feat/a MERGED; run
check "a clean, quiet worktree would go" '[ $rc -eq 0 ] && [[ $out == *"would remove  $T/r/wt-a  feat/a"* ]]'
check "the dry run changes nothing" '[ -d "$W" ] && git -C "$M" rev-parse -q --verify refs/heads/feat/a >/dev/null'
check "the last line counts the run" '[ "$(last)" = "wtclean: 1 to remove, 0 kept (0 merged), 0 errors" ]'
setup; mkwt wt-det feat/det; pr feat/det MERGED; git -C "$W" checkout -q --detach; age "$W"; run
check "a detached worktree is kept" '[[ $out == *"kept"*"wt-det  (detached): detached or locked"* ]]'
setup; mkwt wt-lock feat/lock; pr feat/lock MERGED; git -C "$M" worktree lock "$W"; run
check "a locked worktree is kept" '[[ $out == *"wt-lock  feat/lock: detached or locked"* ]]'
setup; mkwt agent-a1b2 feat/agent; pr feat/agent MERGED; run
check "an agent-* directory is kept" '[[ $out == *"agent-a1b2  feat/agent: agent worktree (agent-* or worktree-agent-*)"* ]]'
setup; mkwt wt-ag worktree-agent-a1b2; pr worktree-agent-a1b2 MERGED; run
check "a worktree-agent-* branch is kept" '[[ $out == *"wt-ag  worktree-agent-a1b2: agent worktree"* ]]'
setup; mkwt wt-gone feat/gone; pr feat/gone MERGED; rm -rf "$W"; run
check "a missing directory is kept" '[[ $out == *"wt-gone  feat/gone: directory missing"* ]]'
setup; mkwt wt-broken feat/broken; pr feat/broken MERGED; printf 'gitdir: %s\n' "$T/nowhere" > "$W/.git"; run
check "a worktree git cannot read is kept, not an error" '[ $rc -eq 0 ] && [[ $out == *"wt-broken  feat/broken: git cannot read it"* ]]'
setup; mkwt wt-lab feat/lab; pr feat/lab MERGED; git -C "$M" config remote.origin.url https://gitlab.com/o/r.git; run
check "a repo without a GitHub remote keeps its worktrees" '[ $rc -eq 0 ] && [[ $out == *"(no GitHub remote)"* ]] && [[ $out == *"wt-lab  feat/lab: no GitHub remote"* ]]'
setup; mkwt wt-a feat/a; pr feat/a MERGED; run_bare --repo "$M"
check "without Orca, --repo names the repo" '[[ $out == *"would remove  $T/r/wt-a"* ]] && [ ! -e "$FAKE/orca.log" ]'
setup; mkwt wt-a feat/a; pr feat/a MERGED; run_bare
check "without Orca or --repo, it scans the repo it runs in" '[[ $out == *"would remove  $T/r/wt-a"* ]]'
setup; WD=$T run_bare
check "without Orca or --repo, outside a repo, is a usage error" '[ $rc -eq 3 ]'
setup; mkwt wt-a feat/a; pr feat/a MERGED; ln -s "$M" "$T/r/link"; run_bare --repo "$T/r/link" --repo "$M"
check "a repo named twice, once through a symlink, is scanned once" '[ "$(grep -c "wt-a" <<<"$out")" -eq 1 ]'
setup; mkwt "wt space" feat/space; pr feat/space MERGED; run
check "a path with a space works" '[[ $out == *"would remove  $T/r/wt space  feat/space"* ]]'
setup; orca_repo "$HOME" folder; orca_repo "$T/r/gone" git; run
check "a folder repo and a missing repo are skipped, not errors" '[ $rc -eq 0 ]'
setup; mkwt wt-a feat/a; mkdir -p "$HOME/.config/orca"; run_bare
check "Orca installed without a CLI on PATH is an error, and bare orca never runs" '[ $rc -eq 2 ] && [[ $out == *"Orca"* ]] && [ ! -e "$FAKE/orca.log" ]'
setup; mkwt wt-a feat/a; ORCA_USER_DATA_PATH=$T/orca-data run_bare
check "ORCA_USER_DATA_PATH without a CLI is an error too" '[ $rc -eq 2 ]'
setup; FAKE_ORCA_FAIL=1 run --check
check "--check after an Orca failure returns 0, not 2" '[ $rc -eq 0 ] && [[ "$(last)" == *", 1 errors" ]]'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
