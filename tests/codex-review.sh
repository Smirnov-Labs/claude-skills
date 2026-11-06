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
printf 'model=%s chars=%s\n' "${model:-none}" "${#stdin}" >> "$FAKE_LOG"
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
git -C "$WD" config --unset diff.relative
echo "uncommitted" >> "$WD/a.txt"
FAKE_MODE=clean run diff main --out "$T/o13"
check "a single ref means REF..HEAD, never the working tree" '[ $rc -eq 0 ] && ! grep -q "uncommitted" "$T/o13/prompt.md"'
git -C "$WD" checkout -q -- a.txt; git -C "$WD" checkout -q main
FAKE_MODE=clean run diff
check "nothing to review is a usage error (3)" '[ $rc -eq 3 ] && [[ $out == *"nothing to review"* ]]'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
