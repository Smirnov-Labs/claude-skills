#!/usr/bin/env bash
# Sandbox test for codex-review: a fake `codex` on PATH plays each failure the
# real one has shown (crash, stale model pin, "could not review", empty or
# unparseable output, a hang), so this never calls Codex or touches ~/.codex.
#   tests/codex-review.sh                  test this checkout's script
#   TOOL=/path/to/codex-review tests/...   test another copy
set -uo pipefail
TOOL=${TOOL:-$(cd "$(dirname "$0")/.." && pwd)/skills/codex-review/bin/codex-review}
T=$(mktemp -d /tmp/codex-review-test.XXXXXX)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export FAKE_LOG=$T/calls.log CODEX_REVIEW_MODEL=
pass=0 fail=0
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc, output was: $out"; fi; }
run() { out=$(cd "$WD" && "$TOOL" "$@" 2>&1); rc=$?; }

mkdir -p "$T/bin"
cat > "$T/bin/codex" <<'EOF'
#!/usr/bin/env bash
model="" outf=""
while [ $# -gt 0 ]; do
  case $1 in -m) model=$2; shift ;; -o) outf=$2; shift ;; esac; shift
done
stdin=$(cat)
printf 'model=%s chars=%s pwd=%s\n' "${model:-none}" "${#stdin}" "$PWD" >> "$FAKE_LOG"
case $FAKE_MODE in
  clean)    printf '## Verdict\nCLEAN\n\n## Findings\nNone.\n' > "$outf" ;;
  major)    printf '## Verdict\nFINDINGS\n\n## Findings\n### [MAJOR] Merge runs before the MERGED check\n- Where: a.sh:3\n\n### [MINOR] Name\n' > "$outf" ;;
  label)    printf '**Verdict:** FINDINGS\n\n1. **[CRITICAL]** Deletes the backup\n' > "$outf" ;;
  crash)    echo "error: unexpected argument '--full-auto' found" >&2; exit 2 ;;
  stale)    if [ -n "$model" ]; then echo "unexpected status 400 Bad Request: {\"detail\":\"The '$model' model is not supported when using Codex with a ChatGPT account.\"}" >&2; exit 1; fi
            printf '## Verdict\nCLEAN\n' > "$outf" ;;
  cant)     printf '## Verdict\nCANNOT REVIEW: the files it names are missing\n' > "$outf" ;;
  cantprose) printf "I couldn't perform the review because the diff was empty.\n" > "$outf" ;;
  empty)    : > "$outf" ;;
  unparsed) printf 'Looks fine to me overall.\n' > "$outf" ;;
  hang)     sleep 30 ;;
  prose)    printf '## Verdict\nFINDINGS\n\nThe merge runs before the check, which loses work.\n' > "$outf" ;;
  incomplete) printf '## Verdict\nINCOMPLETE\n' > "$outf" ;;
  blankhead) printf '\n\n## Unable to review\nI cannot review because the referenced plan is unavailable.\n' > "$outf" ;;
  boldfind) printf '**[MAJOR]** A reply saying "I cannot review this diff" exits 0\n- Where: x\n' > "$outf" ;;
  fenced)   printf '### [MAJOR] The wrapper accepts a refusal\n- Where: x\n\n```\n## Verdict\nCANNOT REVIEW: missing files\n```\n' > "$outf" ;;
  headrefuse) printf '## Unable to review\nI cannot review because the referenced plan is unavailable.\n' > "$outf" ;;
  minoronly) printf '### [MINOR] Naming\n- Where: x\n' > "$outf" ;;
  late)     { printf '### [MINOR] Naming\n'; for i in $(seq 1 30); do echo "detail line $i"; done; printf '## Verdict\nCANNOT REVIEW: the files are missing\n'; } > "$outf" ;;
  fwords)   printf '## Verdict\nFINDINGS: the migration cannot preserve existing records.\n\n### [MAJOR] Loses rows\n' > "$outf" ;;
  quotenov) printf '### [MAJOR] A reply saying "I cannot review this diff" exits 0\n- Where: x\n' > "$outf" ;;
  cleanup)  printf '## Verdict\nCLEANUP REQUIRED\n\nThe merge loses work.\n' > "$outf" ;;
  quoted)   printf '## Verdict\nFINDINGS\n\n## Findings\n### [MAJOR] A reply saying "I can\xe2\x80\x99t review this diff" exits 0\n- Where: x\n' > "$outf" ;;
  contraction) printf "I can't review because the files are unavailable.\n" > "$outf" ;;
  curly)    printf 'I can\xe2\x80\x99t review this diff.\n' > "$outf" ;;
  leftover) if [ -n "$model" ]; then printf '## Verdict\nCLEAN\n' > "$outf"; echo "The '$model' model is not supported when using Codex with a ChatGPT account." >&2; exit 1; fi ;;
  notmodel) echo "error: sandbox mode 'x' is not supported here" >&2; exit 1 ;;
  hangchild) bash -c 'trap "" TERM; sleep 60' & echo $! > "$FAKE_CHILD"; sleep 60 ;;
  *)        echo "fake codex: unknown FAKE_MODE=$FAKE_MODE" >&2; exit 9 ;;
esac
EOF
chmod +x "$T/bin/codex"
export PATH="$T/bin:$PATH"

WD=$T/plain; mkdir -p "$WD"; printf '# Plan\n\n1. Do the thing.\n' > "$WD/plan.md"

FAKE_MODE=clean run plan plan.md --out "$T/o1"
check "clean plan review exits 0" '[ $rc -eq 0 ] && [[ $out == *"verdict CLEAN"* ]]'
check "the run pins the model" 'grep -q "model=gpt-6-astra" "$FAKE_LOG"'
check "outside a repo it passes --skip-git-repo-check" 'grep -q -- "--skip-git-repo-check" "$T/o1/codex.log"'
check "the prompt holds the plan and the format" 'grep -q "Do the thing" "$T/o1/prompt.md" && grep -q "## Verdict" "$T/o1/prompt.md"'

FAKE_MODE=major run spec plan.md --out "$T/o2"
check "a MAJOR finding exits 1 and is listed" '[ $rc -eq 1 ] && [[ $out == *"major 1"* ]] && [[ $out == *"[MAJOR] Merge runs before"* ]]'

FAKE_MODE=label run plan plan.md --out "$T/o2b"
check "bold Verdict label and numbered finding parse" '[ $rc -eq 1 ] && [[ $out == *"critical 1"* ]]'

FAKE_MODE=crash run plan plan.md --out "$T/o3"
check "a crash exits 2 and shows the log tail" '[ $rc -eq 2 ] && [[ $out == *"codex exited 2"* ]] && [[ $out == *"--full-auto"* ]]'

: > "$FAKE_LOG"
FAKE_MODE=stale run plan plan.md --out "$T/o4"
check "a stale pin retries without -m and says so" '[ $rc -eq 0 ] && [[ $out == *"looks stale"* ]] && grep -q "model=none" "$FAKE_LOG"'

FAKE_MODE=cant run plan plan.md --out "$T/o5"
check "CANNOT REVIEW in the verdict exits 2" '[ $rc -eq 2 ] && [[ $out == *"could not review"* ]]'

FAKE_MODE=cantprose run plan plan.md --out "$T/o5b"
check "\"couldn't perform the review\" prose exits 2 despite exit 0" '[ $rc -eq 2 ]'

FAKE_MODE=empty run plan plan.md --out "$T/o6"
check "an empty review exits 2" '[ $rc -eq 2 ] && [[ $out == *"wrote no review"* ]]'

FAKE_MODE=unparsed run plan plan.md --out "$T/o7"
check "an unparsed review exits 1" '[ $rc -eq 1 ] && [[ $out == *"UNPARSED"* ]]'

start=$(date +%s); FAKE_MODE=hang run plan plan.md --out "$T/o8" --timeout 2s; took=$(( $(date +%s) - start ))
check "a hang times out and exits 2" '[ $rc -eq 2 ] && [[ $out == *"timed out"* ]] && [ $took -lt 15 ]'

FAKE_MODE=prose run plan plan.md --out "$T/r1"
check "FINDINGS with prose findings is UNPARSED (1), never CLEAN" '[ $rc -eq 1 ] && [[ $out == *"UNPARSED"* ]]'
FAKE_MODE=incomplete run plan plan.md --out "$T/r2"
check "an unknown verdict is UNPARSED (1)" '[ $rc -eq 1 ] && [[ $out == *"UNPARSED"* ]]'
FAKE_MODE=cleanup run plan plan.md --out "$T/r2b"
check "a verdict that only starts with CLEAN is UNPARSED" '[ $rc -eq 1 ] && [[ $out == *"UNPARSED"* ]]'
FAKE_MODE=quoted run plan plan.md --out "$T/r2c"
check "refusal words inside a finding do not void the review" '[ $rc -eq 1 ] && [[ $out == *"major 1"* ]]'
FAKE_MODE=contraction run plan plan.md --out "$T/r3"
check "\"can't review\" exits 2 in review mode" '[ $rc -eq 2 ]'
FAKE_MODE=contraction run prompt plan.md --out "$T/r4"
check "\"can't review\" exits 2 in prompt mode" '[ $rc -eq 2 ]'
FAKE_MODE=curly run plan plan.md --out "$T/r5"
check "a curly-apostrophe refusal exits 2" '[ $rc -eq 2 ]'
FAKE_MODE=leftover run plan plan.md --out "$T/r6"
check "the retry cannot reuse the failed attempt's review" '[ $rc -eq 2 ] && [[ $out == *"wrote no review"* ]]'
: > "$FAKE_LOG"; FAKE_MODE=notmodel run plan plan.md --out "$T/r7"
check "a non-model \"not supported\" error does not retry" '[ $rc -eq 2 ] && [ "$(wc -l < "$FAKE_LOG")" -eq 1 ]'
export FAKE_CHILD=$T/child.pid; FAKE_MODE=hangchild run plan plan.md --out "$T/r8" --timeout 2s
check "a timeout also kills a child that ignores SIGTERM" '[ $rc -eq 2 ] && ! kill -0 "$(cat "$FAKE_CHILD")" 2>/dev/null'

FAKE_MODE=blankhead run prompt plan.md --out "$T/s0b"
check "blank lines before a refusal heading do not hide it" '[ $rc -eq 2 ]'
FAKE_MODE=boldfind run plan plan.md --out "$T/s0c"
check "a bold finding that quotes a refusal is a finding" '[ $rc -eq 1 ] && [[ $out == *"major 1"* ]]'
FAKE_MODE=fenced run plan plan.md --out "$T/s0d"
check "a verdict inside a code fence is not the verdict" '[ $rc -eq 1 ] && [[ $out == *"major 1"* ]]'
FAKE_MODE=headrefuse run prompt plan.md --out "$T/s0"
check "a refusal under a heading exits 2 in prompt mode" '[ $rc -eq 2 ]'
FAKE_MODE=minoronly run plan plan.md --out "$T/s1"
check "no verdict and only MINOR findings is UNPARSED, not CLEAN" '[ $rc -eq 1 ] && [[ $out == *"UNPARSED"* ]]'
FAKE_MODE=late run plan plan.md --out "$T/s2"
check "a CANNOT verdict late in the review exits 2" '[ $rc -eq 2 ]'
FAKE_MODE=fwords run plan plan.md --out "$T/s3"
check "FINDINGS whose text says cannot is still FINDINGS" '[ $rc -eq 1 ] && [[ $out == *"major 1"* ]]'
FAKE_MODE=quotenov run plan plan.md --out "$T/s4"
check "a finding that quotes a refusal, with no verdict, is FINDINGS" '[ $rc -eq 1 ] && [[ $out == *"major 1"* ]]'
export FAKE_CHILD=$T/child2.pid; rm -f "$FAKE_CHILD"
( cd "$WD" && FAKE_MODE=hangchild exec "$TOOL" plan plan.md --out "$T/s5" --timeout 60 ) > "$T/s5.out" 2>&1 & wpid=$!
for i in $(seq 1 50); do [ -s "$FAKE_CHILD" ] && break; sleep 0.1; done
kill -TERM "$wpid"; wait "$wpid"; rc=$?; out=$(cat "$T/s5.out")
check "SIGTERM to the wrapper stops the Codex run and its children" '[ $rc -eq 130 ] && ! kill -0 "$(cat "$FAKE_CHILD")" 2>/dev/null'
rm -f "$FAKE_CHILD"   # a background job of this non-interactive shell starts with SIGINT ignored
( cd "$WD" && FAKE_MODE=hangchild exec "$TOOL" plan plan.md --out "$T/s6" --timeout 60 ) > "$T/s6.out" 2>&1 & wpid=$!
for i in $(seq 1 50); do [ -s "$FAKE_CHILD" ] && break; sleep 0.1; done
kill -INT "$wpid"; wait "$wpid"; rc=$?; out=$(cat "$T/s6.out")
check "SIGINT to a background wrapper still cancels it" '[ $rc -eq 130 ] && ! kill -0 "$(cat "$FAKE_CHILD")" 2>/dev/null'
rm -f "$FAKE_CHILD"
( cd "$WD" && FAKE_MODE=hangchild exec "$TOOL" plan plan.md --out "$T/s7" --timeout 60 ) > "$T/s7.out" 2>&1 & wpid=$!
for i in $(seq 1 50); do [ -s "$FAKE_CHILD" ] && break; sleep 0.1; done
kill -TERM "$wpid"; sleep 0.5; kill -TERM "$wpid" 2>/dev/null; wait "$wpid"; rc=$?
check "a second signal during cleanup does not leave Codex running" '! kill -0 "$(cat "$FAKE_CHILD")" 2>/dev/null'
mkdir -p "$T/keep"; echo old-review > "$T/keep/review.md"; echo old-log > "$T/keep/codex.log"
FAKE_MODE=crash run plan plan.md --dry-run --out "$T/keep"
check "a dry run keeps an earlier review and log" 'grep -q old-review "$T/keep/review.md" && grep -q old-log "$T/keep/codex.log"'
FAKE_MODE=crash run plan plan.md --dry-run --out "$T/o9"
check "--dry-run never calls codex" '[ $rc -eq 0 ] && [ -s "$T/o9/prompt.md" ] && [ ! -e "$T/o9/review.md" ]'

printf 'my own prompt, sent as is\n' > "$WD/p.md"
FAKE_MODE=clean run prompt p.md --out "$T/o10"
check "prompt mode sends the file verbatim" '[ $rc -eq 0 ] && cmp -s "$WD/p.md" "$T/o10/prompt.md" && [[ $out == *"ANSWERED"* ]]'
FAKE_MODE=clean run prompt p.md --focus x
check "prompt mode refuses --focus" '[ $rc -eq 3 ]'

python3 -c 'print("# Big plan\n" + "x" * 650000)' > "$WD/big.md"; : > "$FAKE_LOG"
FAKE_MODE=clean run plan big.md --out "$T/o11"
check "a huge prompt switches to the 500K model" '[ $rc -eq 0 ] && grep -q "model=gpt-6.1-sol" "$FAKE_LOG"'

run bogus; check "a bad mode is a usage error (3)" '[ $rc -eq 3 ]'
run plan; check "plan without a file is a usage error (3)" '[ $rc -eq 3 ]'

# diff mode: a repo with an origin, main, and a feature branch with one commit
O=$T/origin.git; git init -q --bare "$O"
WD=$T/repo; git init -q -b main "$WD"; git -C "$WD" remote add origin "$O"
echo base > "$WD/a.txt"; git -C "$WD" add -A; git -C "$WD" commit -qm base; git -C "$WD" push -q origin main
git -C "$WD" remote set-head origin main >/dev/null 2>&1
git -C "$WD" checkout -q -b feat; echo "new line" >> "$WD/a.txt"; git -C "$WD" commit -qam "feat: add a line"
FAKE_MODE=clean run diff --out "$T/o12"
check "diff defaults to origin/main...HEAD" '[ $rc -eq 0 ] && [[ $out == *"origin/main...HEAD"* ]]'
check "the diff prompt has the commit and the change" 'grep -q "feat: add a line" "$T/o12/prompt.md" && grep -q "+new line" "$T/o12/prompt.md"'
check "inside a repo there is no --skip-git-repo-check" '! grep -q -- "--skip-git-repo-check" "$T/o12/codex.log"'
mkdir -p "$WD/sub"; echo b > "$WD/sub/b.txt"; git -C "$WD" add -A; git -C "$WD" commit -qm "feat: sub file"
git -C "$WD" config diff.relative true
out=$(cd "$WD/sub" && FAKE_MODE=clean "$TOOL" diff --out results 2>&1); rc=$?
check "diff.relative and a subdirectory do not narrow the diff" '[ $rc -eq 0 ] && grep -q "+new line" "$WD/sub/results/prompt.md"'
check "a relative --out is the same dir for the script and codex" '[ -s "$WD/sub/results/review.md" ]'
: > "$FAKE_LOG"; printf '# p\n' > "$WD/sub/p.md"
out=$(cd "$WD/sub" && FAKE_MODE=clean "$TOOL" plan p.md --out "$T/cwd1" 2>&1); rc=$?
check "plan mode runs Codex in the caller's directory" 'grep -q "pwd=$WD/sub$" "$FAKE_LOG"'
: > "$FAKE_LOG"; out=$(cd "$WD/sub" && FAKE_MODE=clean "$TOOL" diff --out "$T/cwd2" 2>&1); rc=$?
check "diff mode runs Codex at the repo root" 'grep -q "pwd=$WD$" "$FAKE_LOG"'
git -C "$WD" config --unset diff.relative
S=$T/subrepo; git init -q -b main "$S"; echo s > "$S/s.txt"; git -C "$S" add -A; git -C "$S" commit -qm s1
git -C "$WD" -c protocol.file.allow=always submodule --quiet add "$S" mod >/dev/null 2>&1; git -C "$WD" commit -qm "add submodule"
echo s2 >> "$S/s.txt"; git -C "$S" commit -qam s2; git -C "$WD/mod" -c protocol.file.allow=always pull -q 2>/dev/null
git -C "$WD" add mod; git -C "$WD" commit -qm "bump submodule"; git -C "$WD" config diff.ignoreSubmodules all
FAKE_MODE=clean run diff HEAD~1 --out "$T/sm"
check "diff.ignoreSubmodules cannot hide a submodule bump" '[ $rc -eq 0 ] && grep -q "+Subproject commit" "$T/sm/prompt.md"'
git -C "$WD" config --unset diff.ignoreSubmodules
printf 'caf\xe9\n' > "$WD/latin1.txt"; git -C "$WD" add latin1.txt; git -C "$WD" commit -qm "latin-1 file"
FAKE_MODE=clean run diff HEAD~1 --out "$T/l1"
check "a non-UTF-8 file in the diff does not crash the review" '[ $rc -eq 0 ] && grep -q "latin1.txt" "$T/l1/prompt.md"'
echo "uncommitted" >> "$WD/a.txt"
FAKE_MODE=clean run diff main --out "$T/o13"
check "a single ref means REF..HEAD, never the working tree" '[ $rc -eq 0 ] && ! grep -q "uncommitted" "$T/o13/prompt.md"'
git -C "$WD" checkout -q -- a.txt; git -C "$WD" checkout -q main
FAKE_MODE=clean run diff
check "nothing to review is a usage error (3)" '[ $rc -eq 3 ] && [[ $out == *"nothing to review"* ]]'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
