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
# FAKE_GIT_REMOVE_NOOP=1 makes `worktree remove` exit 0 and remove nothing.
import os
import sys

args = sys.argv[1:]
with open(os.path.join(os.environ["FAKE"], "git.log"), "a") as log:
    log.write(" ".join(args) + "\n")
removing = any(a == "worktree" and b == "remove" for a, b in zip(args, args[1:]))
if removing and os.environ.get("FAKE_GIT_REMOVE_FAIL"):
    print("fatal: refused", file=sys.stderr)
    sys.exit(128)
if removing and os.environ.get("FAKE_GIT_REMOVE_NOOP"):
    sys.exit(0)
os.execv(os.environ["REAL_GIT"], [os.environ["REAL_GIT"]] + args)
EOF

cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env python3
# Fake gh: logs its arguments to $FAKE/gh.log. `pr list -R o/r --head B` prints $FAKE/prs/<B, / as __>.json or [],
# at most --limit entries, as gh does. `api repos/o/r/compare/A...B` is answered from the bare origin ($FAKE_ORIGIN).
# FAKE_GH_FAIL=1 plays a 502 and FAKE_GH_GARBAGE=1 an HTML page. Anything else exits 9.
import json
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
    listed = json.load(open(prs)) if os.path.exists(prs) else []
    print(json.dumps(listed[:int(flag("--limit"))] if flag("--limit") else listed))
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
# second call on, `worktree ps` creates FILE before it answers. FAKE_PS2_PY=CODE: from its second call on, it runs
# the Python statements CODE too, before it answers. They see os, json, subprocess, sys and fake (the $FAKE directory).
# FAKE_ORCA_RM_NOOP=1: `worktree rm` says it removed the worktree and removes nothing. FAKE_ORCA_RM_DIRONLY=1: it
# deletes the directory, leaves git's entry for it, and says it removed the worktree.
import json
import os
import shutil
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
    if len(open(os.path.join(fake, "ps.count")).read().splitlines()) >= 2 and os.environ.get("FAKE_PS2_PY"):
        exec(os.environ["FAKE_PS2_PY"])
    sys.stdout.write(open(os.path.join(fake, "ps.json")).read())
    sys.exit(0)
if args[:2] == ["worktree", "rm"] and "--worktree" in args[:-1] and args[args.index("--worktree") + 1].startswith("id:R1::"):
    wt = args[args.index("--worktree") + 1][len("id:R1::"):]
    refused = {"ok": False, "error": {"message": "refused"}}
    listing = git("-C", wt, "worktree", "list", "--porcelain").stdout.splitlines()
    if os.environ.get("FAKE_ORCA_RM_FAIL") or not listing:
        reply(refused, 1)
    if os.environ.get("FAKE_ORCA_RM_NOOP"):
        reply({"ok": True, "result": {"removed": True}})
    if os.environ.get("FAKE_ORCA_RM_DIRONLY"):
        shutil.rmtree(wt)
        reply({"ok": True, "result": {"removed": True}})
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
# pr BRANCH STATE [HEAD] [CROSS] [COUNT]: add COUNT (default 1) pull requests to what the fake gh lists for BRANCH
# (HEAD defaults to the branch tip)
pr() {
  local head=${3:-}
  [ -n "$head" ] || head=$(git -C "$M" rev-parse "refs/heads/$1")
  mkdir -p "$FAKE/prs"
  python3 - "$FAKE/prs/${1//\//__}.json" "$2" "$head" "${4:-false}" "${5:-1}" <<'PY'
import json
import os
import sys

f, state, head, cross, count = sys.argv[1:6]
prs = json.load(open(f)) if os.path.exists(f) else []
for _ in range(int(count)):
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
# sleeping PID: wait, for about 2 seconds at most, until the background subshell PID has run its cd and exec'd sleep.
# Before the exec its comm still reads bash, and its working directory may not be set yet.
sleeping() {
  local n
  for n in {1..20}; do
    [ "$(cat "/proc/$1/comm" 2>/dev/null)" = sleep ] && return 0
    sleep 0.1
  done
  return 1
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
setup; mkwt wt-m feat/m; pr feat/m MERGED; run
check "a merged PR at HEAD: would remove, with its number" '[[ $out == *"would remove  $T/r/wt-m  feat/m  #1"* ]]'
setup; mkwt wt-none feat/none; run
check "no PR keeps it" '[[ $out == *"wt-none  feat/none: no merged pull request"* ]]'
setup; mkwt wt-closed feat/closed; pr feat/closed CLOSED; run
check "a PR closed without merging keeps it" '[[ $out == *"wt-closed  feat/closed: no merged pull request"* ]]'
setup; mkwt wt-open feat/open; pr feat/open MERGED; pr feat/open OPEN; run
check "an open PR keeps it even after an earlier merge" '[[ $out == *"wt-open  feat/open: open pull request #2"* ]]'
setup; mkwt wt-many feat/many; pr feat/many MERGED "" false 100; pr feat/many OPEN; run --apply
check "as many PRs as gh lists at once keep it, so an open one past them counts" '[ -d "$W" ] && git -C "$M" rev-parse -q --verify refs/heads/feat/many >/dev/null && [[ $out == *"wt-many  feat/many: too many pull requests from this branch to check them all"* ]]'
setup; mkwt wt-fork feat/fork; pr feat/fork MERGED "" true; run
check "a merged PR from a fork does not count" '[[ $out == *"wt-fork  feat/fork: no merged pull request"* ]]'
setup; mkwt wt-ahead feat/ahead; pr feat/ahead MERGED; echo x >> "$W/a.txt"; git -C "$W" commit -qam local; age "$W"; run
check "a local commit past the PR head keeps it" '[[ $out == *"wt-ahead  feat/ahead: commits not in the pull request (merged #1)"* ]]'
check "a merged worktree kept for any reason counts as merged" '[ "$(last)" = "wtclean: 0 to remove, 1 kept (1 merged), 0 errors" ]'
setup; mkwt wt-behind feat/behind; OLD=$H; echo y >> "$W/a.txt"; git -C "$W" commit -qam more; git -C "$W" push -q
pr feat/behind MERGED; git -C "$W" reset -q --hard "$OLD"; age "$W"; run
check "HEAD behind a PR head that is present locally would go" '[[ $out == *"would remove  $T/r/wt-behind"* ]]'
setup; mkwt wt-rem feat/rem; git clone -q https://github.com/o/r.git "$T/r/helper"; git -C "$T/r/helper" checkout -q feat/rem
echo z >> "$T/r/helper/a.txt"; git -C "$T/r/helper" commit -qam remote; git -C "$T/r/helper" push -q origin feat/rem
pr feat/rem MERGED "$(git -C "$T/r/helper" rev-parse HEAD)"; run
check "HEAD behind a PR head that is only on GitHub would go, through the compare API" '[[ $out == *"would remove  $T/r/wt-rem"* ]] && grep -q "api repos/o/r/compare/" "$FAKE/gh.log"'
setup; mkwt wt-loc feat/loc; git clone -q https://github.com/o/r.git "$T/r/helper"; git -C "$T/r/helper" checkout -q feat/loc
echo z >> "$T/r/helper/a.txt"; git -C "$T/r/helper" commit -qam remote; git -C "$T/r/helper" push -q origin feat/loc
pr feat/loc MERGED "$(git -C "$T/r/helper" rev-parse HEAD)"; echo l > "$W/b.txt"; git -C "$W" add b.txt; git -C "$W" commit -qm local; age "$W"; run
check "a local-only commit, with a PR head only on GitHub, keeps it" '[[ $out == *"wt-loc  feat/loc: commits not in the pull request"* ]]'
setup; mkwt wt-reuse feat/reuse; pr feat/reuse MERGED; pr feat/reuse CLOSED "$(git -C "$M" rev-parse origin/main)"; run
check "a branch reused by a later closed PR still matches its merged PR" '[[ $out == *"would remove  $T/r/wt-reuse  feat/reuse  #1"* ]]'
setup; mkwt wt-m feat/m; pr feat/m MERGED; FAKE_GH_FAIL=1 run
check "a gh failure is an error: exit 2" '[ $rc -eq 2 ] && [[ $out == *"error"* ]] && [[ "$(last)" == *", 1 errors" ]]'
setup; mkwt wt-m feat/m; pr feat/m MERGED; FAKE_GH_GARBAGE=1 run
check "gh output that is not JSON is an error, not a traceback" '[ $rc -eq 2 ] && [[ $out != *"Traceback"* ]]'
setup; mkwt wt-u feat/u; pr feat/u MERGED; touch "$W/notes.txt"; age "$W"; run
check "an untracked file keeps it" '[[ $out == *"wt-u  feat/u: local files: 1 untracked files (merged #1)"* ]]'
setup; mkwt wt-t feat/t; pr feat/t MERGED; echo edit >> "$W/a.txt"; age "$W"; run
check "a changed tracked file keeps it" '[[ $out == *"wt-t  feat/t: local files: 1 changed tracked files"* ]]'
setup; mkwt wt-au feat/au; pr feat/au MERGED; git -C "$W" update-index --assume-unchanged a.txt; echo edit >> "$W/a.txt"; age "$W"; run
check "an assume-unchanged edit keeps it" '[[ $out == *"wt-au"*"assume-unchanged or skip-worktree"* ]]'
setup; mkwt wt-sparse feat/sparse; mkdir "$W/docs"; echo d > "$W/docs/d.txt"; git -C "$W" add docs; git -C "$W" commit -qm docs; git -C "$W" push -q
pr feat/sparse MERGED; git -C "$W" sparse-checkout set src; age "$W"; run --apply
check "a sparse-checkout worktree stays, and so does its branch" '[ -d "$W" ] && [ ! -e "$W/docs" ] && git -C "$M" rev-parse -q --verify refs/heads/feat/sparse >/dev/null && [[ $out == *"wt-sparse  feat/sparse: local files: 1 tracked files are marked assume-unchanged or skip-worktree"* ]]'
setup; mkwt wt-env feat/env; pr feat/env MERGED; echo S=1 > "$W/.env"; age "$W"; run
check "an ignored .env keeps it" '[[ $out == *"wt-env  feat/env: local files: ignored files that are not build output: .env"* ]]'
setup; mkwt wt-sp1 feat/sp1; pr feat/sp1 MERGED; printf '[ ]*\n' >> "$M/.git/info/exclude"; echo keep > "$W/   "; age "$W"; run --apply
check "an ignored file named only spaces keeps it, and the file stays" '[ -e "$W/   " ] && [[ $out == *"wt-sp1  feat/sp1: local files: ignored files that are not build output:     (merged #1)"* ]]'
setup; mkwt wt-sp2 feat/sp2; pr feat/sp2 MERGED; echo keep > "$W/   "; age "$W"; run --apply
check "an untracked file named only spaces keeps it, and the file stays" '[ -e "$W/   " ] && [[ $out == *"wt-sp2  feat/sp2: local files: 1 untracked files (merged #1)"* ]] && ! grep -q "worktree remove" "$FAKE/git.log"'
setup; mkwt wt-nm feat/nm; pr feat/nm MERGED; mkdir -p "$W/node_modules/x"; echo 1 > "$W/node_modules/x/i.js"; age "$W"; run
check "build output alone does not keep it" '[[ $out == *"would remove  $T/r/wt-nm"* ]]'
setup; git init -q -b main "$T/r/subsrc"; echo s > "$T/r/subsrc/s.txt"; git -C "$T/r/subsrc" add -A; git -C "$T/r/subsrc" commit -qm s
mkwt wt-sub feat/sub; git -C "$W" -c protocol.file.allow=always submodule add -q "$T/r/subsrc" sub; git -C "$W" commit -qm sub; git -C "$W" push -q
pr feat/sub MERGED; age "$W"; run
check "an initialized submodule keeps it" '[[ $out == *"wt-sub  feat/sub: initialized submodules"* ]]'
setup; mkwt wt-new feat/new; pr feat/new MERGED; touch "$(git -C "$W" rev-parse --path-format=absolute --git-path index)"; run
check "a worktree touched in the last 24 hours is kept" '[[ $out == *"wt-new  feat/new: touched in the last 24 hours"* ]]'
setup; mkwt wt-q feat/q; pr feat/q MERGED; run; run
check "a dry run leaves the index alone, so a second run still would remove it" '[[ $out == *"would remove  $T/r/wt-q"* ]]'
setup; mkwt wt-ag feat/ag; pr feat/ag MERGED; orca_row "$W" agents=1 state=done; run
check "an Orca agent in the done state keeps it" '[[ $out == *"wt-ag  feat/ag: in use: 1 agents in Orca"* ]]'
setup; mkwt wt-term feat/term; pr feat/term MERGED; orca_row "$W" live=1; run
check "a live terminal keeps it" '[[ $out == *"wt-term  feat/term: in use: 1 live terminals"* ]]'
setup; mkwt wt-unv feat/unv; pr feat/unv MERGED; orca_row "$W" unverifiable=1; run
check "terminals Orca cannot verify keep it" '[[ $out == *"wt-unv  feat/unv: in use: terminals Orca cannot verify"* ]]'
setup; mkwt wt-pty feat/pty; pr feat/pty MERGED; orca_row "$W" attached=1; run
check "an attached terminal keeps it" '[[ $out == *"wt-pty  feat/pty: in use: a terminal is attached"* ]]'
setup; mkwt wt-par feat/par; pr feat/par MERGED; orca_row "$T/r/child" agents=1 id=CHILD; orca_row "$W" children=CHILD; run
check "a child workspace with an agent keeps its parent" '[[ $out == *"wt-par  feat/par: in use: a child workspace has an agent"* ]]'
setup; mkwt wt-par2 feat/par2; pr feat/par2 MERGED; orca_row "$W" children=MISSING; run
check "a child workspace Orca did not list keeps its parent" '[[ $out == *"wt-par2  feat/par2: in use: a child workspace Orca did not list"* ]]'
setup; mkwt wt-idle feat/idle; pr feat/idle MERGED; orca_row "$W"; run
check "an idle Orca workspace would go" '[[ $out == *"would remove  $T/r/wt-idle"* ]]'
setup; mkwt wt-proc feat/proc; pr feat/proc MERGED; (cd "$W" && exec sleep 300) & P=$!; sleeping "$P"; run; kill "$P"
check "a process working inside keeps it" '[[ $out == *"wt-proc  feat/proc: in use: process $P (sleep) works in it"* ]]'
setup; mkwt wt-pre feat/pre; pr feat/pre MERGED; mkdir -p "$T/r/wt-pre2"; (cd "$T/r/wt-pre2" && exec sleep 300) & P=$!; sleeping "$P"; run; kill "$P"
check "a process in a sibling path that shares the prefix does not count" '[[ $out == *"would remove  $T/r/wt-pre  "* ]]'
setup; mkwt wt-self feat/self; pr feat/self MERGED; WD=$W run
check "running wtclean inside a worktree keeps that worktree" '[[ $out == *"wt-self  feat/self: in use: process"* ]]'
setup; mkwt wt-ln feat/ln; pr feat/ln MERGED; ln -s "$T/r" "$T/rl"; orca_row "$T/rl/wt-ln" agents=1; run
check "Orca rows match by real path" '[[ $out == *"wt-ln  feat/ln: in use: 1 agents in Orca"* ]]'
setup; mkwt wt-m feat/m; pr feat/m MERGED; FAKE_ORCA_FAIL=1 run
check "an Orca failure is an error: exit 2" '[ $rc -eq 2 ] && [[ $out == *"Orca is not running"* ]]'
setup; mkwt wt-m feat/m; pr feat/m MERGED; orca_ps_patch 'd["result"]["truncated"] = True'; run
check "a truncated Orca list is an error" '[ $rc -eq 2 ] && [[ $out == *"error"* ]]'
setup; mkwt wt-m feat/m; pr feat/m MERGED; orca_row "$W"; orca_ps_patch 'd["result"]["totalCount"] += 1'; run
check "an Orca list whose count does not match its rows is an error" '[ $rc -eq 2 ]'
setup; mkwt wt-m feat/m; pr feat/m MERGED; orca_row "$W"; orca_ps_patch 'del d["result"]["worktrees"][0]["agents"]'; run
check "an Orca row without its agents field is an error" '[ $rc -eq 2 ]'
setup; mkwt wt-m feat/m; pr feat/m MERGED; orca_ps_patch 'd["result"]["hostScope"]["hostIds"] = ["runtime:other"]'; run
check "an Orca list from another host is an error" '[ $rc -eq 2 ]'
setup; mkwt wt-dup feat/dup; pr feat/dup MERGED; orca_row "$W"; orca_row "$W" id=R2::dup; run
check "a worktree Orca lists twice is kept" '[[ $out == *"wt-dup  feat/dup: Orca lists it more than once"* ]]'
setup; mkwt wt-deep feat/deep; pr feat/deep MERGED; orca_row "$W"; mkdir "$W/pkg"; (cd "$W/pkg" && exec sleep 300) & P=$!; sleeping "$P"; run; kill "$P"
check "a process in a subdirectory keeps a worktree that Orca lists as idle" '[[ $out == *"wt-deep  feat/deep: in use: process $P (sleep) works in it"* ]]'
setup; mkwt wt-m feat/m; pr feat/m MERGED; orca_row "$W"; orca_ps_patch 'd["result"]["worktrees"][0]["agents"] = None'; run
check "an Orca row with a null agents field is an error" '[ $rc -eq 2 ] && [[ $out == *"agents"* ]]'
setup; mkwt wt-m feat/m; pr feat/m MERGED; orca_ps_patch 'd["ok"] = False; d["error"] = {"message": "worktree ps failed"}'; run
check "a failed Orca worktree list is an error" '[ $rc -eq 2 ] && [[ $out == *"worktree ps failed"* ]]'
setup; mkwt wt-h feat/h; pr feat/h MERGED; run --apply
check "apply removes a hidden worktree with git, without --force" '[ $rc -eq 0 ] && [ ! -d "$W" ] && grep -q "worktree remove $W" "$FAKE/git.log" && ! grep -q -- "--force" "$FAKE/git.log"'
check "apply deletes the branch at the PR head and prints its SHA" '! git -C "$M" rev-parse -q --verify refs/heads/feat/h >/dev/null && [[ $out == *"deleted branch feat/h (was ${H:0:10})"* ]]'
check "apply leaves the remote branch alone" '[ -n "$(git -C "$M" ls-remote origin refs/heads/feat/h)" ]'
check "apply never prunes" '! grep -q "worktree prune" "$FAKE/git.log"'
check "apply deletes the branch only if it is still at the PR head" 'grep -q "update-ref -d refs/heads/feat/h $H" "$FAKE/git.log"'
check "the last line counts removals" '[ "$(last)" = "wtclean: 1 removed, 0 kept (0 merged), 0 errors" ]'
setup; mkwt wt-o feat/o; pr feat/o MERGED; orca_row "$W"; run --apply
check "apply removes an Orca worktree through Orca, by id" '[ ! -d "$W" ] && grep -q -- "worktree rm --worktree id:R1::$W --json" "$FAKE/orca.log"'
setup; mkwt wt-ob feat/ob; pr feat/ob MERGED; orca_row "$W"; FAKE_ORCA_DELETES_BRANCH=1 run --apply
check "a branch Orca already deleted is reported, not an error" '[ $rc -eq 0 ] && [[ $out == *"branch feat/ob was already deleted"* ]]'
setup; mkwt wt-behind feat/behind; OLD=$H; echo y >> "$W/a.txt"; git -C "$W" commit -qam more; git -C "$W" push -q
pr feat/behind MERGED; git -C "$W" reset -q --hard "$OLD"; age "$W"; run --apply
check "a worktree behind the PR head goes, and its branch stays" '[ ! -d "$W" ] && git -C "$M" rev-parse -q --verify refs/heads/feat/behind >/dev/null && [[ $out == *"kept branch feat/behind: it is at ${OLD:0:7}, not the PR head"* ]]'
setup; mkwt wt-late feat/late; pr feat/late MERGED; orca_row "$W"; FAKE_PS2_TOUCH="$W/late.txt" run --apply
check "a file that appears after the first checks keeps the worktree" '[ -d "$W" ] && [ -e "$W/late.txt" ] && [[ $out == *"wt-late  feat/late: local files"* ]]'
setup; mkwt wt-ag feat/ag; pr feat/ag MERGED; orca_row "$W"
FAKE_PS2_PY='d = json.load(open(fake + "/ps.json")); d["result"]["worktrees"][0]["agents"] = [{"state": "working"}]; json.dump(d, open(fake + "/ps.json", "w"))' run --apply
check "an agent that appears after the scan keeps it" '[ -d "$W" ] && [[ $out == *"wt-ag  feat/ag: in use: 1 agents in Orca (merged #1)"* ]] && ! grep -q "worktree rm" "$FAKE/orca.log"'
setup; mkwt wt-24 feat/24; pr feat/24 MERGED; orca_row "$W"
FAKE_PS2_PY="os.utime('$(git -C "$W" rev-parse --path-format=absolute --git-path index)')" run --apply
check "a worktree touched after the scan keeps it" '[ -d "$W" ] && [[ $out == *"wt-24  feat/24: touched in the last 24 hours (merged #1)"* ]]'
setup; mkwt wt-sm feat/sm; pr feat/sm MERGED; orca_row "$W"
FAKE_PS2_PY="os.makedirs('$(git -C "$W" rev-parse --path-format=absolute --git-path modules)')" run --apply
check "a submodule that appears after the scan keeps it" '[ -d "$W" ] && [[ $out == *"wt-sm  feat/sm: initialized submodules (merged #1)"* ]]'
setup; mkwt wt-ref feat/ref; pr feat/ref MERGED; orca_row "$W"; FAKE_ORCA_RM_FAIL=1 run --apply
check "an Orca failure during removal stops the run with an error" '[ $rc -eq 2 ] && [ -d "$W" ] && [[ $out == *"error"*"refused"* ]]'
setup; mkwt wt-noop feat/noop; pr feat/noop MERGED; orca_row "$W"; FAKE_ORCA_RM_NOOP=1 run --apply
check "Orca says removed but the directory stays: an error" '[ $rc -eq 2 ] && [ -d "$W" ] && [[ $out == *"error"*"still there"* ]]'
setup; mkwt wt-dir feat/dir; pr feat/dir MERGED; orca_row "$W"; FAKE_ORCA_RM_DIRONLY=1 run --apply
check "Orca deletes the directory but git still lists it: an error" '[ $rc -eq 2 ] && [ ! -d "$W" ] && [[ $out == *"error"*"still there"* ]]'
setup; mkwt wt-gr feat/gr; pr feat/gr MERGED; FAKE_GIT_REMOVE_FAIL=1 run --apply
check "a git refusal keeps the worktree, not an error" '[ $rc -eq 0 ] && [ -d "$W" ] && [[ $out == *"wt-gr  feat/gr: git refused the removal: fatal: refused"* ]]'
setup; mkwt wt-gn feat/gn; pr feat/gn MERGED; FAKE_GIT_REMOVE_NOOP=1 run --apply
check "git exits 0 but the directory stays: kept, not removed" '[ $rc -eq 0 ] && [ -d "$W" ] && [[ $out == *"wt-gn  feat/gn: git refused the removal: still present (merged #1)"* ]]'
setup; mkwt wt-s1 feat/s; pr feat/s MERGED; git -C "$M" worktree add -q -f "$T/r/wt-s2" feat/s; run --apply
check "a branch another worktree has checked out is kept" '[ ! -d "$T/r/wt-s1" ] && git -C "$M" rev-parse -q --verify refs/heads/feat/s >/dev/null && [[ $out == *"kept branch feat/s: another worktree has it checked out"* ]]'
setup; mkwt wt-c feat/c; pr feat/c MERGED; run --check
check "--check with something to remove: exit 0, one line, no change" '[ $rc -eq 0 ] && [ "$out" = "wtclean: 1 can go, 0 errors" ] && [ -d "$W" ]'
setup; mkwt wt-c feat/c; run --check
check "--check with nothing to do: exit 1" '[ $rc -eq 1 ] && [ "$out" = "wtclean: 0 can go, 0 errors" ]'
setup; mkwt wt-c feat/c; pr feat/c MERGED; FAKE_GH_FAIL=1 run --check
check "--check after a tool error: exit 0" '[ $rc -eq 0 ] && [ "$out" = "wtclean: 0 can go, 1 errors" ]'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
