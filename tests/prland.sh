#!/usr/bin/env bash
# Sandbox test for prland: fake `gh`, `prbots` and Orca CLI on PATH, real git repos and
# worktrees under a temp dir, so it never talks to GitHub or Orca or touches your checkouts.
#   tests/prland.sh                  test this checkout's script
#   TOOL=/path/to/prland tests/...   test another copy
set -uo pipefail
TOOL=${TOOL:-$(cd "$(dirname "$0")/.." && pwd)/skills/pr-land/bin/prland}
T=$(mktemp -d /tmp/prland-test.XXXXXX)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1 FAKE=$T/fake
unset ORCA_CLI_COMMAND   # outside Orca, unless a test names the fake Orca CLI with orun
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc, output was: $out"; fi; }
run() { out=$(cd "$WD" && "$TOOL" "$@" 2>&1); rc=$?; }
orun() { ORCA_CLI_COMMAND=$T/bin/orca run "$@"; }    # like run, inside Orca

mkdir -p "$T/bin" "$FAKE"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
head=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["headRefOid"])' "$FAKE/pr.json" 2>/dev/null)
case "$1 $2" in
  "repo view") echo "{\"nameWithOwner\":\"o/r\",\"url\":\"https://${FAKE_REPO_HOST:-github.com}/o/r\"}" ;;
  "pr view") if [ "${3:-}" = "--json" ]; then echo '{"number":7}'; else cat "$FAKE/pr.json"; fi ;;
  "pr merge")
    printf 'cwd=%s args=%s\n' "$PWD" "$*" >> "$FAKE/merge.log"
    if [ -n "${FAKE_MERGE_FAIL:-}" ]; then echo "GraphQL: Head branch was modified" >&2; exit 1; fi
    case "$*" in *--disable-auto*) printf 'disable-auto\n' >> "$FAKE/api.log"; exit 0 ;; esac
    if [ -n "${FAKE_AUTO_MERGE:-}" ]; then   # GitHub queues an auto-merge instead of merging
      python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['autoMergeRequest']={'enabledAt':'x'}; json.dump(d,open(p,'w'))" "$FAKE/pr.json"; exit 0
    fi
    python3 - "$FAKE/pr.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["state"]="MERGED"; d["mergeCommit"]={"oid":"abcdef0123456789"}
json.dump(d,open(p,"w"))
PY
    if [ -n "${FAKE_MOVE_REMOTE:-}" ]; then   # someone pushes to the PR branch right after the merge
      git -C "$FAKE_HELPER" fetch -q origin feat && git -C "$FAKE_HELPER" checkout -q -B late origin/feat &&
      echo late >> "$FAKE_HELPER/late.txt" && git -C "$FAKE_HELPER" add -A && git -C "$FAKE_HELPER" commit -qm late &&
      git -C "$FAKE_HELPER" push -q origin late:feat
    fi ;;
  "api repos/o/r/git/ref/heads/feat")   # the remote branch as GitHub sees it: the bare origin's ref
    sha=$(git -C "$FAKE_ORIGIN" rev-parse -q --verify refs/heads/feat) || exit 1
    echo "{\"object\":{\"sha\":\"$sha\"}}" ;;
  "api repos/o/r") echo '{"node_id":"R_fake"}' ;;
  "api graphql")
    case "$*" in *mergeQueue*)
      if [ -n "${FAKE_MERGE_QUEUE:-}" ]; then echo '{"data":{"repository":{"mergeQueue":{"id":"MQ_1"}}}}'; else echo '{"data":{"repository":{"mergeQueue":null}}}'; fi
      exit 0 ;; esac
    # updateRefs: compare-and-delete on the bare origin, like GitHub's beforeOid
    before=""; for a in "$@"; do case $a in before=*) before=${a#before=} ;; esac; done
    printf 'graphql before=%s\n' "$before" >> "$FAKE/api.log"
    if git -C "$FAKE_ORIGIN" update-ref -d refs/heads/feat "$before" 2>/dev/null; then echo '{"data":{"updateRefs":{"clientMutationId":null}}}'
    else echo '{"data":{"updateRefs":null},"errors":[{"message":"twirp error not_found: missing"}]}'; exit 1; fi ;;
  *) echo "fake gh: unexpected: $*" >&2; exit 9 ;;
esac
EOF
cat > "$T/bin/prbots" <<'EOF'
#!/usr/bin/env bash
printf 'args=%s\n' "$*" >> "$FAKE/prbots.log"
head=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["headRefOid"])' "$FAKE/pr.json")
: "${FAKE_VERDICT:?prbots should not have been called}"
printf '{"repo":"%s","number":%s,"head":"%s","verdict":"%s","progress":"sar done","sar":{"title":"ok"},"codex":{"status":"none"},"ci":{"failing":[],"pending":[]}}\n' \
  "${FAKE_PB_REPO:-o/r}" "${FAKE_PB_NUMBER:-7}" "${FAKE_PB_HEAD:-$head}" "$FAKE_VERDICT"
EOF
cat > "$T/bin/orca" <<'EOF'
#!/usr/bin/env python3
# Fake Orca CLI: logs its arguments to $FAKE/orca.log and answers `worktree ps` from $FAKE/ps.json. `worktree rm
# --worktree id:R1::<path>` removes that worktree with git. --force, a call without --json, and any command it does not
# know exit 9. FAKE_ORCA_FAIL=1: every call says Orca is not running. FAKE_ORCA_RM_FAIL=1: `worktree rm` refuses.
# FAKE_ORCA_RM_NOOP=1: `worktree rm` says it removed the worktree and removes nothing.
# From its second call on, `worktree ps` answers from $FAKE/ps.next.json if it exists, as if Orca changed meanwhile.
# FAKE_PS2_TOUCH=FILE: from its second call on, `worktree ps` writes FILE before it answers.
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


if os.environ.get("FAKE_ORCA_FAIL"):
    reply({"ok": False, "error": {"message": "Orca is not running"}}, 1)
if "--force" in args or args[-1:] != ["--json"]:
    sys.exit(9)
if args[:2] == ["worktree", "ps"]:
    with open(os.path.join(fake, "ps.count"), "a") as count:
        count.write("x\n")
    later = len(open(os.path.join(fake, "ps.count")).read().splitlines()) >= 2
    if later and os.environ.get("FAKE_PS2_TOUCH"):
        with open(os.environ["FAKE_PS2_TOUCH"], "w") as f:
            f.write("LOCAL=1\n")
    nxt = os.path.join(fake, "ps.next.json")
    sys.stdout.write(open(nxt if later and os.path.exists(nxt) else os.path.join(fake, "ps.json")).read())
    sys.exit(0)
if args[:3] == ["worktree", "set", "--worktree"]:
    reply({"ok": True, "result": {"worktree": {}}})
if args[:3] == ["worktree", "rm", "--worktree"] and args[3].startswith("id:R1::"):
    if os.environ.get("FAKE_ORCA_RM_FAIL"):
        reply({"ok": False, "error": {"message": "refused"}}, 1)
    if os.environ.get("FAKE_ORCA_RM_NOOP"):
        reply({"ok": True, "result": {"removed": True}})
    wt = args[3][len("id:R1::"):]
    listing = subprocess.run(["git", "-C", wt, "worktree", "list", "--porcelain"], capture_output=True, text=True)
    main = listing.stdout.splitlines()[0][len("worktree "):]
    r = subprocess.run(["git", "-C", main, "worktree", "remove", wt], capture_output=True, text=True)
    if r.returncode != 0:
        reply({"ok": False, "error": {"message": r.stderr.strip()}}, 1)
    reply({"ok": True, "result": {"removed": True}})
print("fake orca: unexpected: " + " ".join(args), file=sys.stderr)
sys.exit(9)
EOF
# A fake lsof, on PATH only for the tests that name $T/lsofbin. It logs its arguments to $FAKE/lsof.log.
# FAKE_LSOF=fail: it exits 1 and prints nothing. FAKE_LSOF=partial: it prints process 1, then exits 1. FAKE_LSOF=empty:
# it prints nothing and exits 0. Otherwise it prints, in the form of lsof -F, process 1 working in / and process 4242
# ("fake  proc") working in $FAKE_LSOF_CWD, each with the f line that macOS's lsof adds.
mkdir -p "$T/lsofbin"
cat > "$T/lsofbin/lsof" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE/lsof.log"
case "${FAKE_LSOF:-}" in
  fail) exit 1 ;;
  partial) printf 'p1\ncinit\nfcwd\nn/\n'; exit 1 ;;
  empty) exit 0 ;;
esac
printf 'p1\ncinit\nfcwd\nn/\np4242\ncfake  proc\nfcwd\nn%s\n' "${FAKE_LSOF_CWD:-/}"
EOF
chmod +x "$T/bin/gh" "$T/bin/prbots" "$T/bin/orca" "$T/lsofbin/lsof"
export PATH="$T/bin:$PATH"

# sleeping PID: wait, about 2 seconds at most, until the background subshell PID has run its cd and exec'd sleep.
# A process that never gets there counts as a failed check, so a process test cannot pass without its process.
sleeping() {
  local i
  for i in $(seq 20); do
    case "$(ps -o comm= -p "$1" 2>/dev/null)" in *sleep) return 0 ;; esac
    sleep 0.1
  done
  fail=$((fail+1)); echo "FAIL process $1 did not exec sleep within 2 seconds"
}
stop() { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }

# orca_row PATH [agents=N] [live=N] [children=ID,...] [id=ID] [host=H]: add a row to the fake `worktree ps` answer
# ($PS_FILE, default $FAKE/ps.json)
orca_row() {
  local p=$1; shift
  python3 - "${PS_FILE:-$FAKE/ps.json}" "$p" "$@" <<'PY'
import json
import sys

f, row_path = sys.argv[1:3]
kw = dict(a.split("=", 1) for a in sys.argv[3:])
d = json.load(open(f))
d["result"]["worktrees"].append({
    "worktreeId": kw.get("id") or "R1::" + row_path, "path": row_path, "hostId": kw.get("host", "local"),
    "agents": [{"state": "working"} for _ in range(int(kw.get("agents", 0)))],
    "liveTerminalCount": int(kw.get("live", 0)), "unverifiableTerminalCount": 0, "hasAttachedPty": False,
    "childWorktreeIds": [c for c in kw.get("children", "").split(",") if c]})
d["result"]["totalCount"] += 1
with open(f, "w") as out:
    json.dump(d, out)
PY
}

# origin (bare, reached through insteadOf), the main checkout, and a worktree on branch feat with one
# pushed commit. A helper clone then lands the squash commit on origin/main, as GitHub would.
setup() {
  rm -rf "$T/r" "$FAKE"/*; mkdir -p "$T/r"
  O=$T/r/origin.git; git init -q --bare -b main "$O"; export FAKE_ORIGIN=$O
  git config --file "$GIT_CONFIG_GLOBAL" url."$O".insteadOf "https://github.com/o/r.git"
  M=$T/r/main; git init -q -b main "$M"; git -C "$M" remote add origin https://github.com/o/r.git
  echo base > "$M/a.txt"; printf '.env\nnode_modules/\n' > "$M/.gitignore"; git -C "$M" add -A
  git -C "$M" commit -qm base; git -C "$M" push -q -u origin main
  W=$T/r/wt-feat; git -C "$M" worktree add -q -b feat "$W" origin/main
  echo feature >> "$W/a.txt"; git -C "$W" commit -qam "feat: thing"; git -C "$W" push -q -u origin feat
  HEADSHA=$(git -C "$W" rev-parse HEAD)
  export FAKE_HELPER=$T/r/helper; git clone -q https://github.com/o/r.git "$FAKE_HELPER"; echo feature >> "$FAKE_HELPER/a.txt"
  git -C "$FAKE_HELPER" commit -qam "Title (#7)"; git -C "$FAKE_HELPER" push -q origin main; SQUASH=$(git -C "$FAKE_HELPER" rev-parse HEAD)
  printf '{"number":7,"title":"Title","state":"%s","isDraft":%s,"headRefName":"feat","headRefOid":"%s","baseRefName":"main","url":"https://github.com/o/r/pull/7","isCrossRepository":%s,"mergeCommit":null}\n' \
    "${1:-OPEN}" "${2:-false}" "$HEADSHA" "${3:-false}" > "$FAKE/pr.json"
  printf '{"ok":true,"result":{"worktrees":[],"totalCount":0,"truncated":false,"hostScope":{"hostIds":["local"]}}}\n' > "$FAKE/ps.json"
  WD=$M
}
remote_has_feat() { [ -n "$(git -C "$M" ls-remote origin refs/heads/feat)" ]; }

setup; FAKE_VERDICT=CLEAN run 7
check "clean PR: exit 0" '[ $rc -eq 0 ]'
check "merge is squash, -R, the full head SHA and a (#7) subject" 'grep -q -- "--squash" "$FAKE/merge.log" && grep -q -- "-R o/r" "$FAKE/merge.log" && grep -q -- "--match-head-commit $HEADSHA" "$FAKE/merge.log" && grep -q -- "--subject Title (#7)" "$FAKE/merge.log"'
check "gh merges from outside every checkout" '! grep -q "cwd=$T/r" "$FAKE/merge.log"'
check "the remote branch is deleted by a compare-and-delete on the PR head" '! remote_has_feat && [[ $out == *"remote   deleted feat"* ]] && grep -q "before=$HEADSHA" "$FAKE/api.log"'
check "the PR worktree is removed" '[ ! -d "$W" ] && ! git -C "$M" worktree list | grep -q wt-feat'
check "the local branch is deleted and its SHA printed" '! git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"deleted feat (was ${HEADSHA:0:10})"* ]]'
check "the main checkout fast-forwards to the squash commit" '[ "$(git -C "$M" rev-parse HEAD)" = "$SQUASH" ]'

setup; FAKE_VERDICT="PENDING" run 7
check "PENDING: exit 1 and no merge" '[ $rc -eq 1 ] && [ ! -e "$FAKE/merge.log" ] && [ -d "$W" ]'
setup; FAKE_VERDICT=CLEAN FAKE_PB_HEAD=0000000000000000000000000000000000000001 run 7
check "a CLEAN verdict for another head does not merge" '[ $rc -eq 1 ] && [ ! -e "$FAKE/merge.log" ]'
setup; FAKE_VERDICT=CLEAN FAKE_PB_REPO=x/y run 7
check "a verdict for another repo does not merge" '[ $rc -eq 1 ] && [ ! -e "$FAKE/merge.log" ]'
setup; FAKE_VERDICT=CLEAN run 7 --need sra
check "a misspelled --need is a usage error" '[ $rc -eq 3 ] && [ ! -e "$FAKE/merge.log" ]'
setup; FAKE_VERDICT=CLEAN run 7 --need " sar , ci"
check "--need goes to prbots normalized" 'grep -q -- "--need sar,ci" "$FAKE/prbots.log"'
setup; FAKE_VERDICT=CLEAN run 7 --need all,ci
check "--need all expands to every bot" 'grep -q -- "--need codex,sar,ci" "$FAKE/prbots.log"'
setup; FAKE_VERDICT=CLEAN run -R o/r
check "-R without a PR number is a usage error" '[ $rc -eq 3 ] && [ ! -e "$FAKE/merge.log" ]'
setup; FAKE_VERDICT=CLEAN run https://github.com/other/project/pull/7 -R o/r
check "a PR URL from another repo with -R o/r is refused" '[ $rc -eq 3 ] && [ ! -e "$FAKE/merge.log" ]'
setup; FAKE_VERDICT=CLEAN run https://github.com/o/r/pull/7
check "a PR URL names the repo" '[ $rc -eq 0 ] && grep -q -- "-R o/r" "$FAKE/merge.log"'

setup; touch "$W/notes.txt"; FAKE_VERDICT=CLEAN run 7
check "an untracked file keeps the worktree and the branch" '[ $rc -eq 0 ] && [ -e "$W/notes.txt" ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"untracked"* ]]'
setup; git -C "$W" config status.showUntrackedFiles no; touch "$W/hidden.txt"; FAKE_VERDICT=CLEAN run 7
check "status.showUntrackedFiles=no does not hide untracked work" '[ -e "$W/hidden.txt" ]'
setup; git -C "$W" update-index --assume-unchanged a.txt; echo local-edit >> "$W/a.txt"; FAKE_VERDICT=CLEAN run 7
check "an assume-unchanged file with local edits keeps the worktree" '[ -d "$W" ] && grep -q local-edit "$W/a.txt"'
setup; git -C "$W" update-index --skip-worktree a.txt; echo local-edit >> "$W/a.txt"; FAKE_VERDICT=CLEAN run 7
check "a skip-worktree file with local edits keeps the worktree" '[ -d "$W" ] && grep -q local-edit "$W/a.txt"'
setup; echo SECRET=1 > "$W/.env"; FAKE_VERDICT=CLEAN run 7
check "an ignored .env keeps the worktree" '[ -e "$W/.env" ] && [[ $out == *".env"* ]]'
setup; echo SECRET=1 > "$W/.env"; FAKE_VERDICT=CLEAN run 7 --allow-ignored
check "--allow-ignored lets it go" '[ ! -d "$W" ]'
setup; echo SECRET=1 > "$W/.env"; echo more >> "$W/a.txt"; git -C "$W" commit -qam extra; FAKE_VERDICT=CLEAN run 7 --allow-ignored
check "--allow-ignored still keeps a worktree with commits past the PR head" '[ -d "$W" ] && [[ $out == *"not on the PR head"* ]]'
setup; mkdir -p "$W/node_modules/x"; echo 1 > "$W/node_modules/x/i.js"; FAKE_VERDICT=CLEAN run 7
check "build output alone (node_modules) does not keep the worktree" '[ ! -d "$W" ]'
setup; printf '.nx/\n' >> "$M/.git/info/exclude"; mkdir -p "$W/.nx/cache"; echo 1 > "$W/.nx/cache/run.json"; FAKE_VERDICT=CLEAN run 7
check "an Nx cache (.nx) alone does not keep the worktree" '[ ! -d "$W" ]'
setup; printf '.nx*\n' >> "$M/.git/info/exclude"; echo keep > "$W/.nxrc"; FAKE_VERDICT=CLEAN run 7
check "an ignored file whose name only starts with .nx keeps the worktree" '[ -e "$W/.nxrc" ]'
setup; echo more >> "$W/a.txt"; git -C "$W" commit -qam extra; FAKE_VERDICT=CLEAN run 7
check "a local commit past the PR head keeps the worktree" '[ -d "$W" ] && [[ $out == *"not on the PR head"* ]]'

setup MERGED; run 7
check "already merged: no gate, no merge, still cleans up" '[ $rc -eq 0 ] && [ ! -e "$FAKE/merge.log" ] && [ ! -e "$FAKE/prbots.log" ] && [ ! -d "$W" ]'
setup OPEN true; FAKE_VERDICT=CLEAN run 7
check "a draft: exit 1" '[ $rc -eq 1 ] && [ ! -e "$FAKE/merge.log" ]'
setup; FAKE_VERDICT=CLEAN FAKE_MERGE_QUEUE=1 run 7
check "a base branch with a merge queue is refused before any merge" '[ $rc -eq 1 ] && [ ! -e "$FAKE/merge.log" ]'
setup; FAKE_VERDICT=CLEAN FAKE_AUTO_MERGE=1 PRLAND_CONFIRM_WAIT=1 run 7
check "a queued auto-merge is cancelled and nothing is cleaned" '[ $rc -eq 2 ] && grep -q disable-auto "$FAKE/api.log" && [ -d "$W" ] && remote_has_feat'
setup; FAKE_VERDICT=CLEAN FAKE_MERGE_FAIL=1 run 7
check "a failed merge: exit 2 and nothing cleaned" '[ $rc -eq 2 ] && [ -d "$W" ] && remote_has_feat'
setup; FAKE_VERDICT=CLEAN FAKE_MOVE_REMOTE=1 run 7
check "a push after the merge keeps the remote branch" '[ $rc -eq 0 ] && remote_has_feat && [[ $out == *"remote   kept feat"* ]]'
setup OPEN false true; FAKE_VERDICT=CLEAN run 7
check "a fork PR: remote and local branches left alone" '[ $rc -eq 0 ] && [ -d "$W" ] && remote_has_feat && [[ $out == *"fork PR"* ]]'

setup; echo dirty >> "$M/a.txt"; FAKE_VERDICT=CLEAN run 7
check "a main checkout with tracked changes is not synced" '[[ $out == *"changed tracked files"* ]] && [ "$(git -C "$M" rev-parse HEAD)" != "$SQUASH" ]'
setup; git -C "$FAKE_HELPER" reset -q --hard HEAD~1; echo tracked-now > "$FAKE_HELPER/.env"; git -C "$FAKE_HELPER" add -f .env
git -C "$FAKE_HELPER" commit -qm "Title (#7)"; git -C "$FAKE_HELPER" push -q -f origin main; echo LOCAL-SECRET > "$M/.env"
FAKE_VERDICT=CLEAN run 7
check "sync never overwrites an ignored file the new commits start tracking" 'grep -q LOCAL-SECRET "$M/.env" && [[ $out == *"fast-forward failed"* ]]'
setup; git -C "$M" config remote.origin.pushurl "$T/r/fork.git"; git init -q --bare -b main "$T/r/fork.git"; git -C "$W" push -q "$T/r/fork.git" feat
FAKE_VERDICT=CLEAN run 7
check "the remote delete goes to the verified repo, not a pushurl" '! remote_has_feat && [ -n "$(git -C "$T/r/fork.git" for-each-ref refs/heads/feat)" ]'
setup; git -C "$M" branch -q --set-upstream-to=origin/feat main; FAKE_VERDICT=CLEAN run 7
check "sync uses origin/<base>, not main's configured upstream" '[ "$(git -C "$M" rev-parse HEAD)" = "$SQUASH" ]'
setup; git -C "$M" worktree remove "$W"; git -C "$M" checkout -q feat; FAKE_VERDICT=CLEAN run 7
check "the branch in the main checkout is never switched or deleted" '[ "$(git -C "$M" symbolic-ref --short HEAD)" = feat ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"switch it yourself"* ]]'
setup; rm -rf "$W"; FAKE_VERDICT=CLEAN run 7
check "a PR worktree gone from disk loses its registration, and its branch goes" '! git -C "$M" worktree list | grep -q wt-feat && ! git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null'
setup; git -C "$M" worktree add -q -b other "$T/r/wt-other" origin/main; rm -rf "$T/r/wt-other"; FAKE_VERDICT=CLEAN run 7
check "an unrelated missing worktree keeps its registration (no global prune)" 'git -C "$M" worktree list | grep -q wt-other'

setup; FAKE_VERDICT=CLEAN run 7 --dry-run
check "--dry-run merges, deletes and removes nothing" '[ $rc -eq 0 ] && [ ! -e "$FAKE/merge.log" ] && [ -d "$W" ] && remote_has_feat && [[ $out == *"would run: gh pr merge"* ]]'
setup; WD=$T; FAKE_VERDICT=CLEAN run 7 -R o/r
check "outside a checkout: merged, remote branch deleted, local cleanup skipped" '[ $rc -eq 0 ] && ! remote_has_feat && [[ $out == *"not run from a checkout"* ]]'
setup; FAKE_VERDICT=CLEAN FAKE_REPO_HOST=ghe.example.com run 7
check "a checkout on another host is refused" '[ $rc -eq 3 ] && [ ! -e "$FAKE/merge.log" ]'
setup; python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['url']='https://ghe.example.com/o/r/pull/7'; json.dump(d,open(p,'w'))" "$FAKE/pr.json"
FAKE_VERDICT=CLEAN GH_HOST=ghe.example.com run https://ghe.example.com/o/r/pull/7
check "a PR on another host never cleans up a github.com checkout" '[ -d "$W" ] && [[ $out == *"not run from a checkout"* ]]'
setup; FAKE_VERDICT=CLEAN GH_HOST=ghe.example.com run https://github.com/o/r/pull/7
check "a github.com URL while gh talks to another host is refused" '[ $rc -eq 3 ] && [ ! -e "$FAKE/merge.log" ]'
setup; python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['url']='https://github.com/x/y/pull/7'; json.dump(d,open(p,'w'))" "$FAKE/pr.json"; FAKE_VERDICT=CLEAN run 7
check "a PR whose URL names another repo is refused" '[ $rc -eq 2 ] && [ ! -e "$FAKE/merge.log" ]'
setup; git -C "$M" config url."$T/r/fork.git".pushInsteadOf https://github.com/o/r.git; git init -q --bare -b main "$T/r/fork.git"; git -C "$W" push -q "$T/r/fork.git" feat; FAKE_VERDICT=CLEAN run 7
check "pushInsteadOf cannot redirect the remote delete" '! remote_has_feat && [ -n "$(git -C "$T/r/fork.git" for-each-ref refs/heads/feat)" ]'
setup; WD=$W; FAKE_VERDICT=CLEAN run
check "from inside the PR worktree: merges, and keeps the worktree and the branch, because the shell works in it" '[ $rc -eq 0 ] && grep -q -- "--squash" "$FAKE/merge.log" && [ -d "$W" ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"left in place: process "*" works in it"* ]]'

# Processes that work in the worktree. On Linux prland reads /proc. PRLAND_PROC_ROOT names a missing directory to
# take the lsof path that macOS uses.
setup; (cd "$W" && exec sleep 300) & P=$!; sleeping "$P"; FAKE_VERDICT=CLEAN run 7; stop "$P"
check "a process working in the worktree keeps it and the branch, and names the process" '[ $rc -eq 0 ] && [ -d "$W" ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"$W left in place: process $P (sleep) works in it"* ]]'
setup; mkdir "$W/sub"; (cd "$W/sub" && exec sleep 300) & P=$!; sleeping "$P"; FAKE_VERDICT=CLEAN run 7; stop "$P"
check "a process in a subdirectory keeps it" '[ -d "$W" ] && [[ $out == *"process $P (sleep) works in it"* ]]'
setup; mkdir -p "$T/r/wt-feat2"; (cd "$T/r/wt-feat2" && exec sleep 300) & P=$!; sleeping "$P"; FAKE_VERDICT=CLEAN run 7; stop "$P"
check "a process in a sibling path that shares the prefix does not count" '[ ! -d "$W" ] && [[ $out == *"removed $W"* ]]'
setup; mkdir "$W/sub"; PATH="$T/lsofbin:$PATH" PRLAND_PROC_ROOT=$T/noproc FAKE_LSOF_CWD=$W/sub FAKE_VERDICT=CLEAN run 7
check "without /proc, lsof finds a process in it, and prland keeps it" '[ -d "$W" ] && grep -qxF -- "-w -d cwd -F pcn" "$FAKE/lsof.log" && [[ $out == *"left in place: process 4242 (fake proc) works in it"* ]]'
setup; PATH="$T/lsofbin:$PATH" PRLAND_PROC_ROOT=$T/noproc FAKE_LSOF_CWD=$T/r/wt-feat2 FAKE_VERDICT=CLEAN run 7
check "without /proc, a worktree that lsof shows no process in goes" '[ ! -d "$W" ] && [ -s "$FAKE/lsof.log" ]'
setup; PATH="$T/lsofbin:$PATH" PRLAND_PROC_ROOT=$T/noproc FAKE_LSOF=fail FAKE_VERDICT=CLEAN run 7
check "a process list that cannot be read keeps it, and the merge still counts" '[ $rc -eq 0 ] && [ -d "$W" ] && [[ $out == *"left in place: cannot list processes: lsof exited 1"* ]]'
setup; PATH="$T/lsofbin:$PATH" PRLAND_PROC_ROOT=$T/noproc FAKE_LSOF=partial FAKE_VERDICT=CLEAN run 7
check "an lsof that lists some processes and then fails keeps it" '[ -d "$W" ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"left in place: cannot list processes: lsof exited 1"* ]]'
setup; PATH="$T/lsofbin:$PATH" PRLAND_PROC_ROOT=$T/noproc FAKE_LSOF=empty FAKE_VERDICT=CLEAN run 7
check "an lsof that lists no process at all keeps it" '[ -d "$W" ] && [[ $out == *"left in place: cannot list processes: lsof listed none"* ]]'
if command -v lsof >/dev/null; then
  setup; (cd "$W" && exec sleep 300) & P=$!; sleeping "$P"; PRLAND_PROC_ROOT=$T/noproc FAKE_VERDICT=CLEAN run 7; stop "$P"
  check "the real lsof finds a process in it" '[ -d "$W" ] && [[ $out == *"process $P (sleep) works in it"* ]]'
fi
same_check() { python3 - "$(dirname "$TOOL")/../../cleaning-merged-worktrees/bin/wtclean" "$TOOL" <<'PY'
import re
import sys

def body(fp):
    m = re.search(r"^def cwd_users\(path\):\n.*?(?=^def |\Z)", open(fp).read(), re.S | re.M)
    return m.group(0).rstrip() if m else None

sys.exit(0 if body(sys.argv[1]) and body(sys.argv[1]) == body(sys.argv[2]) else 1)
PY
}
if [ -e "$(dirname "$TOOL")/../../cleaning-merged-worktrees/bin/wtclean" ]; then
  rc=0 out="cwd_users differs"; check "prland and wtclean hold the same process check" 'same_check'
fi
# cwd_users() on the lsof path, called directly. lsof prints a backslash as \\, a control character as \t or ^A, and
# DEL as \x7f. It prints a non-ASCII character as it is in a UTF-8 locale and as \xNN otherwise, and every other
# character, a caret too, as it is. FAKE_LSOF_CWD below is what lsof prints for the busy directory.
lsof_unit() { PATH="$T/lsofbin:$PATH" PRLAND_PROC_ROOT=$T/noproc python3 - "$TOOL" "$T" <<'PY'
import os
import runpy
import sys

tool, t = sys.argv[1], os.path.realpath(sys.argv[2])
g = runpy.run_path(tool, run_name="lsof_unit")
bad, BUSY = [], [(4242, "fake proc")]


def case(label, where, want, cwd="/", mode=""):
    os.environ["FAKE_LSOF_CWD"], os.environ["FAKE_LSOF"] = cwd, mode
    try:
        got = g["cwd_users"](where)
    except g["ToolError"] as e:
        got = "ToolError: %s" % e
    if not (got == want if isinstance(want, list) else str(got).startswith(want)):
        bad.append("%s: got %r" % (label, got))


case("a tab", t + "/wt\ttab", BUSY, cwd=t + "/wt\\ttab/sub")
case("a tab, idle", t + "/wt\ttab", [])
# lsof prints the control character ^A and a literal caret and A alike, so an idle wt<^A>x beside a busy wt^Ax also
# counts as in use: a false keep, never a miss.
case("a control character", t + "/wt\x01x", BUSY, cwd=t + "/wt^Ax")
case("DEL", t + "/wt\x7fx", BUSY, cwd=t + "/wt\\x7fx")
case("a caret and an A", t + "/wt^Ax", BUSY, cwd=t + "/wt^Ax")
case("a caret and an A, then a tab", t + "/wt^A\ttab", BUSY, cwd=t + "/wt^A\\ttab")
case("a caret and an A, then a backslash", t + "/wt^A\\b", BUSY, cwd=t + "/wt^A\\\\b")
case("a backslash", t + "/wt\\b", BUSY, cwd=t + "/wt\\\\b")
case("a backslash, idle", t + "/wt\\b", [])
case("a backslash and a t, idle, beside a busy tab", t + "/wt\\tx", [], cwd=t + "/wt\\tx")
case("non-ASCII, UTF-8 locale", t + "/José/wt", BUSY, cwd=t + "/José/wt/sub")
case("non-ASCII, C locale", t + "/José/wt", BUSY, cwd=t + "/Jos\\xc3\\xa9/wt")
case("non-ASCII parent, caret and an A", t + "/José/wt^A", BUSY, cwd=t + "/Jos\\xc3\\xa9/wt^A")
case("non-ASCII parent, idle", t + "/José/wt", [], cwd=t + "/Jos\\xc3\\xa9/other")
case("an escape in a subdirectory", t + "/plain", BUSY, cwd=t + "/plain/sub\\tdir")
case("a sibling that only an escape makes look alike", t + "/plain", [], cwd=t + "/plain\\x2dx")
case("an idle plain path", t + "/plain", [])
case("a failed run with output", t + "/plain", "ToolError: cannot list processes: lsof exited 1", mode="partial")
case("no output", t + "/plain", "ToolError: cannot list processes: lsof listed none", mode="empty")
print("\n".join(bad) or "ok")
sys.exit(1 if bad else 0)
PY
}
out=$(lsof_unit 2>&1); rc=$?
check "cwd_users on the lsof path: escaped paths, partial and empty lists" '[ $rc -eq 0 ]'

# Inside Orca ($ORCA_CLI_COMMAND set). orca_calls prints the worktree ps, set and rm calls, in order, on one line.
orca_calls() { grep -o -E "^worktree (ps|set|rm)" "$FAKE/orca.log" 2>/dev/null | sed 's/^worktree //' | tr '\n' ' '; }
setup; orca_row "$W"; FAKE_VERDICT=CLEAN orun 7
check "Orca: an idle worktree goes through Orca's worktree rm, by id, with no --force" '[ $rc -eq 0 ] && [ ! -d "$W" ] && grep -qxF -- "worktree rm --worktree id:R1::$W --json" "$FAKE/orca.log" && [[ $out == *"removed $W through Orca"* ]]'
check "Orca: its card is marked completed, and Orca's list is read again just before the removal" 'grep -qxF -- "worktree set --worktree id:R1::$W --workspace-status completed --json" "$FAKE/orca.log" && [ "$(orca_calls)" = "ps set ps rm " ]'
check "Orca: the branch still goes by the atomic update-ref" '! git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"deleted feat (was ${HEADSHA:0:10})"* ]]'
setup; cp "$FAKE/ps.json" "$FAKE/ps.next.json"; orca_row "$W"; PS_FILE=$FAKE/ps.next.json orca_row "$W" live=1; FAKE_VERDICT=CLEAN orun 7
check "Orca: a terminal that opens after the first read keeps it" '[ -d "$W" ] && [ "$(orca_calls)" = "ps set ps " ] && [[ $out == *"Orca shows a terminal in it"* ]]'
setup; cp "$FAKE/ps.json" "$FAKE/ps.next.json"; PS_FILE=$FAKE/ps.next.json orca_row "$W" live=1; FAKE_VERDICT=CLEAN orun 7
check "Orca: a worktree that Orca starts to list after the first read, with a terminal, keeps it" '[ -d "$W" ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [ "$(orca_calls)" = "ps ps " ] && [[ $out == *"Orca shows a terminal in it"* ]]'
setup; orca_row "$W"; FAKE_PS2_TOUCH=$W/.env FAKE_VERDICT=CLEAN orun 7
check "Orca: an ignored .env that appears during the second read keeps it" '[ -e "$W/.env" ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && ! grep -q "worktree rm" "$FAKE/orca.log" && [[ $out == *"not build output: .env"* ]]'
setup; orca_row "$W" agents=1; FAKE_VERDICT=CLEAN orun 7
check "Orca: an agent in it keeps the worktree and the branch, and the card says completed" '[ -d "$W" ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [ "$(orca_calls)" = "ps set ps " ] && [[ $out == *"left in place: Orca shows an agent in it"* ]]'
setup; orca_row "$W" live=1; WD=$W; FAKE_VERDICT=CLEAN orun
check "Orca: prland run from a terminal inside it keeps it" '[ $rc -eq 0 ] && [ -d "$W" ] && [ "$(orca_calls)" = "ps set ps " ] && [[ $out == *"Orca shows a terminal in it"* ]]'
setup; orca_row "$T/r/kid" agents=1 id=R1::kid; orca_row "$W" children=R1::kid; FAKE_VERDICT=CLEAN orun 7
check "Orca: a child workspace with an agent keeps it" '[ -d "$W" ] && [[ $out == *"Orca shows an agent in a child workspace"* ]]'
setup; orca_row "$T/r/kid" live=1 id=R1::kid; orca_row "$W" children=R1::kid; FAKE_VERDICT=CLEAN orun 7
check "Orca: a child workspace with a terminal keeps it" '[ -d "$W" ] && [[ $out == *"Orca shows a terminal in a child workspace"* ]]'
setup; orca_row "$T/r/gk" agents=1 id=R1::gk; orca_row "$T/r/kid" id=R1::kid children=R1::gk,R1::kid; orca_row "$W" children=R1::kid
FAKE_VERDICT=CLEAN orun 7
check "Orca: an agent in a grandchild keeps it, and a child that lists itself ends the walk" '[ -d "$W" ] && [[ $out == *"Orca shows an agent in a child workspace"* ]]'
setup; orca_row "$W" children=R1::gone; FAKE_VERDICT=CLEAN orun 7
check "Orca: a child workspace that Orca did not list keeps it" '[ -d "$W" ] && [[ $out == *"Orca did not list"* ]]'
setup; orca_row "$W"; orca_row "$W" id=R2::dup; FAKE_VERDICT=CLEAN orun 7
check "Orca: a worktree that Orca lists twice stays, and no card is touched" '[ -d "$W" ] && [ "$(orca_calls)" = "ps ps " ] && [[ $out == *"Orca lists it more than once"* ]]'
setup; orca_row "$W"; FAKE_VERDICT=CLEAN FAKE_ORCA_FAIL=1 orun 7
check "Orca: an unreadable worktree list keeps it, and the merge still counts" '[ $rc -eq 0 ] && [ -d "$W" ] && [ "$(orca_calls)" = "ps ps " ] && [[ $out == *"left in place: Orca'"'"'s worktree list could not be read in full: Orca is not running"* ]]'
setup; orca_row "$W"; FAKE_VERDICT=CLEAN FAKE_ORCA_RM_FAIL=1 orun 7
check "Orca: a refused worktree rm keeps the worktree and the branch" '[ -d "$W" ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"remove failed, left in place: refused"* ]]'
setup; orca_row "$W"; FAKE_VERDICT=CLEAN FAKE_ORCA_RM_NOOP=1 orun 7
check "Orca: a worktree rm that says removed but leaves the worktree keeps the branch" '[ -d "$W" ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"Orca said it removed it, but it is still on disk"* ]]'
setup; orca_row "$W"; touch "$W/notes.txt"; FAKE_VERDICT=CLEAN orun 7
check "Orca: local files keep it, and the card says completed" '[ -e "$W/notes.txt" ] && [ "$(orca_calls)" = "ps set ps " ] && [[ $out == *"untracked"* ]]'
setup; orca_row "$W"; FAKE_VERDICT=CLEAN orun 7 --keep-worktree
check "Orca: --keep-worktree still marks the card completed" '[ -d "$W" ] && [ "$(orca_calls)" = "ps set " ] && [[ $out == *"$W completed in Orca"* ]]'
setup; orca_row "$W"; FAKE_VERDICT=CLEAN orun 7 --dry-run
check "Orca: --dry-run changes nothing in Orca" '[ -d "$W" ] && [ "$(orca_calls)" = "ps ps " ] && [[ $out == *"would remove worktree $W through Orca"* ]] && [[ $out == *"would mark the Orca card of $W completed"* ]]'
setup; orca_row "$W" host=runtime:other; FAKE_VERDICT=CLEAN orun 7
check "Orca: a worktree that Orca lists only for another host goes through git" '[ ! -d "$W" ] && [ "$(orca_calls)" = "ps ps " ] && [[ $out == *"removed $W"* ]] && [[ $out != *"through Orca"* ]]'
setup; FAKE_VERDICT=CLEAN orun 7
check "Orca: a worktree that Orca does not list goes through git" '[ ! -d "$W" ] && [ "$(orca_calls)" = "ps ps " ]'
setup OPEN false true; orca_row "$W"; FAKE_VERDICT=CLEAN orun 7
check "Orca: a fork PR touches no card" '[ -d "$W" ] && [ ! -e "$FAKE/orca.log" ]'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
