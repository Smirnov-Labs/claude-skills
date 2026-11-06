#!/usr/bin/env bash
# Sandbox test for prland: fake `gh` and `prbots` on PATH, real git repos and
# worktrees under a temp dir, so it never talks to GitHub or touches your checkouts.
#   tests/prland.sh                  test this checkout's script
#   TOOL=/path/to/prland tests/...   test another copy
set -uo pipefail
TOOL=${TOOL:-$(cd "$(dirname "$0")/.." && pwd)/skills/pr-land/bin/prland}
T=$(mktemp -d /tmp/prland-test.XXXXXX)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1 FAKE=$T/fake
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc, output was: $out"; fi; }
run() { out=$(cd "$WD" && "$TOOL" "$@" 2>&1); rc=$?; }

mkdir -p "$T/bin" "$FAKE"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
head=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["headRefOid"])' "$FAKE/pr.json" 2>/dev/null)
case "$1 $2" in
  "repo view") echo '{"nameWithOwner":"o/r"}' ;;
  "pr view") if [ "${3:-}" = "--json" ]; then echo '{"number":7}'; else cat "$FAKE/pr.json"; fi ;;
  "pr merge")
    printf 'cwd=%s args=%s\n' "$PWD" "$*" >> "$FAKE/merge.log"
    if [ -n "${FAKE_MERGE_FAIL:-}" ]; then echo "GraphQL: Head branch was modified" >&2; exit 1; fi
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
  "api repos/o/r/git/ref/heads/feat") echo "{\"object\":{\"sha\":\"$head\"}}" ;;
  "api -X") printf '%s\n' "$*" >> "$FAKE/api.log" ;;
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
chmod +x "$T/bin/gh" "$T/bin/prbots"
export PATH="$T/bin:$PATH"

# origin (bare, reached through insteadOf), the main checkout, and a worktree on branch feat with one
# pushed commit. A helper clone then lands the squash commit on origin/main, as GitHub would.
setup() {
  rm -rf "$T/r" "$FAKE"/*; mkdir -p "$T/r"
  O=$T/r/origin.git; git init -q --bare -b main "$O"
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
  WD=$M
}
remote_has_feat() { [ -n "$(git -C "$M" ls-remote origin refs/heads/feat)" ]; }

setup; FAKE_VERDICT=CLEAN run 7
check "clean PR: exit 0" '[ $rc -eq 0 ]'
check "merge is squash, -R, the full head SHA and a (#7) subject" 'grep -q -- "--squash" "$FAKE/merge.log" && grep -q -- "-R o/r" "$FAKE/merge.log" && grep -q -- "--match-head-commit $HEADSHA" "$FAKE/merge.log" && grep -q -- "--subject Title (#7)" "$FAKE/merge.log"'
check "gh merges from outside every checkout" '! grep -q "cwd=$T/r" "$FAKE/merge.log"'
check "the remote branch is deleted, with a lease" '! remote_has_feat && [[ $out == *"remote   deleted feat"* ]]'
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
setup; FAKE_VERDICT=CLEAN run 7 --need sar,ci
check "--need goes to prbots" 'grep -q -- "--need sar,ci" "$FAKE/prbots.log"'
setup; FAKE_VERDICT=CLEAN run https://github.com/other/project/pull/7 -R o/r
check "a PR URL from another repo with -R o/r is refused" '[ $rc -eq 3 ] && [ ! -e "$FAKE/merge.log" ]'
setup; FAKE_VERDICT=CLEAN run https://github.com/o/r/pull/7
check "a PR URL names the repo" '[ $rc -eq 0 ] && grep -q -- "-R o/r" "$FAKE/merge.log"'

setup; touch "$W/notes.txt"; FAKE_VERDICT=CLEAN run 7
check "an untracked file keeps the worktree and the branch" '[ $rc -eq 0 ] && [ -e "$W/notes.txt" ] && git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"untracked"* ]]'
setup; git -C "$W" config status.showUntrackedFiles no; touch "$W/hidden.txt"; FAKE_VERDICT=CLEAN run 7
check "status.showUntrackedFiles=no does not hide untracked work" '[ -e "$W/hidden.txt" ]'
setup; echo SECRET=1 > "$W/.env"; FAKE_VERDICT=CLEAN run 7
check "an ignored .env keeps the worktree" '[ -e "$W/.env" ] && [[ $out == *".env"* ]]'
setup; echo SECRET=1 > "$W/.env"; FAKE_VERDICT=CLEAN run 7 --allow-ignored
check "--allow-ignored lets it go" '[ ! -d "$W" ]'
setup; mkdir -p "$W/node_modules/x"; echo 1 > "$W/node_modules/x/i.js"; FAKE_VERDICT=CLEAN run 7
check "build output alone (node_modules) does not keep the worktree" '[ ! -d "$W" ]'
setup; echo more >> "$W/a.txt"; git -C "$W" commit -qam extra; FAKE_VERDICT=CLEAN run 7
check "a local commit past the PR head keeps the worktree" '[ -d "$W" ] && [[ $out == *"not on the PR head"* ]]'

setup MERGED; run 7
check "already merged: no gate, no merge, still cleans up" '[ $rc -eq 0 ] && [ ! -e "$FAKE/merge.log" ] && [ ! -e "$FAKE/prbots.log" ] && [ ! -d "$W" ]'
setup OPEN true; FAKE_VERDICT=CLEAN run 7
check "a draft: exit 1" '[ $rc -eq 1 ] && [ ! -e "$FAKE/merge.log" ]'
setup; FAKE_VERDICT=CLEAN FAKE_MERGE_FAIL=1 run 7
check "a failed merge: exit 2 and nothing cleaned" '[ $rc -eq 2 ] && [ -d "$W" ] && remote_has_feat'
setup; FAKE_VERDICT=CLEAN FAKE_MOVE_REMOTE=1 run 7
check "a push after the merge keeps the remote branch (lease)" '[ $rc -eq 0 ] && remote_has_feat && [[ $out == *"remote   kept feat"* ]]'
setup OPEN false true; FAKE_VERDICT=CLEAN run 7
check "a fork PR: remote and local branches left alone" '[ $rc -eq 0 ] && [ -d "$W" ] && remote_has_feat && [[ $out == *"fork PR"* ]]'

setup; echo dirty >> "$M/a.txt"; FAKE_VERDICT=CLEAN run 7
check "a main checkout with tracked changes is not synced" '[[ $out == *"changed tracked files"* ]] && [ "$(git -C "$M" rev-parse HEAD)" != "$SQUASH" ]'
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
check "outside a checkout: merged, remote branch deleted through the API, local cleanup skipped" '[ $rc -eq 0 ] && grep -q "DELETE repos/o/r/git/refs/heads/feat" "$FAKE/api.log" && [[ $out == *"not run from a checkout"* ]]'
setup; WD=$W; FAKE_VERDICT=CLEAN run
check "from inside the PR worktree: removes it, deletes the branch, says cd" '[ $rc -eq 0 ] && [ ! -d "$W" ] && ! git -C "$M" rev-parse -q --verify refs/heads/feat >/dev/null && [[ $out == *"your shell was inside it"* ]]'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
