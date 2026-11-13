#!/usr/bin/env bash
# Sandbox test for prbots: a fake `gh` on PATH serves canned GraphQL snapshots of one
# PR (acme/webapp#42), so it never talks to GitHub. A snapshot is one moment of the
# PR's Codex comments and threads. After prbots comments, each poll swaps in the next
# snapshot from a queue, which plays Codex answering "@codex review". The last checks
# run prland against the same fake, through this prbots.
#   tests/prbots.sh                  test this checkout's script
#   TOOL=/path/to/prbots tests/...   test another copy
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOL=${TOOL:-$ROOT/skills/watching-pr-bot-reviews/bin/prbots}
PRLAND=${PRLAND:-$ROOT/skills/pr-land/bin/prland}
T=$(mktemp -d /tmp/prbots-test.XXXXXX)
export FAKE=$T/fake
unset GH_HOST PRBOTS_CODEX_LOGIN PRBOTS_SAR_LOGIN
pass=0 fail=0 out="" rc=0 took=0
check() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "     exit $rc after ${took}s, output was: $out"; fi; }
run() { local t0=$SECONDS; out=$(cd "$T" && "$TOOL" "$@" 2>&1); rc=$?; took=$((SECONDS - t0)); }
land() { out=$(cd "$T" && "$PRLAND" "$@" 2>&1); rc=$?; took=0; }
has() { [[ $out == *"$1"* ]]; }
json() { printf '%s' "$out" | jq -e "$1" >/dev/null 2>&1; }
use() { rm -f "$FAKE"/*.log "$FAKE/queue"; cp "$FAKE/snap/$1.json" "$FAKE/page.json"; }
comments() { if [ -e "$FAKE/comments.log" ]; then wc -l < "$FAKE/comments.log" | tr -d ' '; else echo 0; fi; }

mkdir -p "$T/bin" "$FAKE/snap"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
# `api graphql` prints $FAKE/page.json, after swapping in the next snapshot named in
# $FAKE/queue. `pr comment` logs the comment and loads the names in $FAKE_THEN into the queue.
case "$1 $2" in
  "api graphql")
    case "$*" in *mergeQueue*) echo '{"data":{"repository":{"mergeQueue":null}}}'; exit 0 ;; esac
    if [ -s "$FAKE/queue" ]; then
      read -r next < "$FAKE/queue"
      tail -n +2 "$FAKE/queue" > "$FAKE/queue.new"; mv "$FAKE/queue.new" "$FAKE/queue"
      cp "$FAKE/snap/$next.json" "$FAKE/page.json"
    fi
    cat "$FAKE/page.json" ;;
  "pr comment")
    printf '%s\n' "$*" >> "$FAKE/comments.log"
    for s in ${FAKE_THEN:-}; do echo "$s"; done > "$FAKE/queue" ;;
  "pr view") cat "$FAKE/prview.json" ;;
  "pr merge") printf '%s\n' "$*" >> "$FAKE/merge.log" ;;
  "api repos/acme/webapp/actions/workflows") ;;
  *) echo "fake gh: unexpected: $*" >&2; exit 9 ;;
esac
EOF
for c in sudo systemctl; do printf '#!/bin/sh\necho "fake %s: not expected here" >&2\nexit 9\n' "$c" > "$T/bin/$c"; done
chmod +x "$T/bin"/*
ln -s "$TOOL" "$T/bin/prbots"   # prland calls prbots from PATH
export PATH="$T/bin:$PATH"

# The snapshots. HEAD 56d1b7b was committed before the PR opened, so Codex ran on its own
# when the PR opened. Codex's summary comment is edited in place: its state JSON and its
# Code Review row are written here the way Codex writes them.
cat > "$T/snap.py" <<'PY'
import json, os, sys
HEAD, OLD = "56d1b7b" + "0" * 33, "3c1f9e2" + "0" * 33
CODEX, URL = "chatgpt-codex-connector", "https://github.com/acme/webapp/pull/42"

def summary(status, at, findings=None, sha=HEAD):
    st = {"code_review": {"commit_sha": sha, "has_any_findings": findings, "has_unresolved_findings": findings, "status": status},
          "security_review": {"commit_sha": None, "has_any_findings": None, "has_unresolved_findings": None, "status": None}}
    when = '<relative-time datetime="%s">%s</relative-time>' % (at, at)
    cell = {"failed": "❌ **Failed** %s<br/>We couldn’t complete this review. Comment `@codex review` to try again." % when,
            "running": "⏳ **Running** %s" % when, "completed": "✅ **Completed** %s" % when}[status]
    body = ("<!-- codex-pull-request-review-summary -->\n<!-- codex-review-state:v1 %s -->\n\n"
            "| | Status | Commit | Trigger |\n|---|---|---|---|\n| 📝 **Code Review** | %s | `%s` | PR opened |\n"
            % (json.dumps(st, separators=(",", ":")), cell, sha[:7]))
    return {"author": {"login": CODEX}, "createdAt": "2026-10-20T09:56:00Z", "url": URL + "#issuecomment-1", "body": body}

def limit(at):   # the comment Codex posts when it is over its usage limit
    return {"author": {"login": CODEX}, "createdAt": at, "url": URL + "#issuecomment-2",
            "body": "You have reached your Codex usage limits for code reviews. You can see your limits in the "
                    "[Codex usage dashboard](https://chatgpt.com/codex/cloud/settings/usage). To continue using code "
                    "reviews, add credits to your account and enable them for code reviews in your "
                    "[settings](https://chatgpt.com/settings/code-review)."}

def ask(at):
    return {"author": {"login": "dev"}, "createdAt": at, "url": URL + "#issuecomment-3", "body": "@codex review"}

def finding(sev):
    body = ("**<sub><sub>![%s Badge](https://img.shields.io/badge/%s-yellow?style=flat)</sub></sub>  Expire refresh "
            "tokens on logout**\n\nLogout leaves the refresh token valid.\n\nUseful? React with 👍 / 👎.\n"
            "<!-- codex-code-review-finding -->" % (sev, sev))
    return {"isResolved": False, "isOutdated": False, "comments": {"nodes": [{"author": {"login": CODEX},
            "path": "src/auth/session.ts", "line": 51, "originalLine": 51, "body": body, "originalCommit": {"oid": HEAD}}]}}

def page(comments, threads=(), committed="2026-10-20T09:50:00Z"):
    pr = {"number": 42, "url": URL, "state": "OPEN", "isDraft": False, "createdAt": "2026-10-20T09:55:00Z",
          "headRefName": "fix/session-timeout", "headRefOid": HEAD, "ready": {"nodes": []}, "forced": {"nodes": []},
          "commits": {"nodes": [{"commit": {"oid": HEAD, "committedDate": committed, "statusCheckRollup": None}}]},
          "reviews": {"nodes": []}, "reviewThreads": {"nodes": list(threads)},
          "comments": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": comments}}
    return {"data": {"repository": {"pullRequest": pr}}}

FAILED = summary("failed", "2026-10-20T10:03:19.112779Z", True)   # failed, yet the flags say findings
LIMIT, ASK = limit("2026-10-20T10:03:21Z"), ask("2026-10-20T10:10:00Z")
DONE = "2026-10-20T10:14:00Z"
snaps = {
    "failed": page([FAILED, LIMIT]),                                     # the usage limit, on PR open
    "failed-nolimit": page([FAILED]),                                    # failed, cause unknown
    "failed-stale-limit": page([limit("2026-10-20T09:40:00Z"), FAILED]),  # that limit comment predates HEAD
    "failed-older": page([summary("failed", "2026-10-20T09:45:00Z", True, OLD)]),
    "failed-asked": page([FAILED, LIMIT, ASK]),                          # a retry asked for, no answer yet
    # a quick retry: before the usage-limit comment lands, or in the same second as the failure
    "late-limit": page([FAILED, ask("2026-10-20T10:03:20Z"), limit("2026-10-20T10:03:21Z")]),
    "same-second": page([FAILED, ask("2026-10-20T10:03:19Z")]),
    "failed-again": page([summary("failed", "2026-10-20T10:10:30.5Z", True), LIMIT, ASK, limit("2026-10-20T10:10:31Z")]),
    "running": page([summary("running", "2026-10-20T10:10:20Z"), LIMIT, ASK]),
    "clean": page([summary("completed", DONE, False), LIMIT, ASK]),
    "findings": page([summary("completed", DONE, True)], [finding("P2")]),
    "findings-unlisted": page([summary("completed", DONE, True)]),       # threads past the last 50
    "pushed": page([], committed="2026-10-20T10:20:00Z"),                 # HEAD pushed after the PR opened
}
for name, snap in snaps.items():
    json.dump(snap, open(os.path.join(sys.argv[1], "snap", name + ".json"), "w"))
json.dump({"number": 42, "title": "Fix session timeout", "state": "OPEN", "isDraft": False, "headRefName": "fix/session-timeout",
           "headRefOid": HEAD, "baseRefName": "main", "url": URL, "isCrossRepository": False, "mergeCommit": None,
           "autoMergeRequest": None}, open(os.path.join(sys.argv[1], "prview.json"), "w"))
PY
python3 -I "$T/snap.py" "$FAKE" || { echo "could not write the snapshots"; exit 1; }

# (a) Codex hit its usage limit on HEAD: that is a failed review, not findings
use failed; run 42 -R acme/webapp --need codex
want='codex  ✗ review failed @56d1b7b (usage limit) · comment "@codex review" to retry'
check "failed review: status exits 0 and says the review failed, with the usage limit" '[ $rc -eq 0 ] && has "$want"'
check "failed review: no findings reported" '! has findings'
check "failed review: verdict PENDING, waiting on codex" 'has "verdict PENDING — waiting on: codex"'
run 42 -R acme/webapp --need codex --json
q='.codex.status == "failed" and .codex.on_head and (.codex.done | not) and .codex.findings == []
   and .codex.has_findings == null and .codex.unresolved == null and .codex.usage_limit
   and .codex.failed_at == "2026-10-20T10:03:19Z" and (.codex.retry_requested | not)'
check "failed review: --json says failed on HEAD, no finding flags, usage limit" 'json "$q"'
q='.verdict == "PENDING" and .waiting == ["codex"] and .blocking == [] and .fixes == [] and .stalled == []
   and .trigger_candidates == [{"bot": "codex", "body": "@codex review", "grace": 0, "why": "review failed on HEAD 56d1b7b (usage limit)"}]'
check "failed review: --json verdict PENDING, and codex is to be asked again at once" 'json "$q"'
run wait 42 -R acme/webapp --need codex --timeout 12s --interval 1
want='x codex review failed on HEAD 56d1b7b (usage limit); re-run with --trigger (or comment "@codex review")'
check "failed review: wait without --trigger exits 2 at once and says how to retry" '[ $rc -eq 2 ] && [ $took -lt 6 ] && has "$want"'

use failed-nolimit; run 42 -R acme/webapp --need codex
check "no usage-limit comment: failed, and the usage limit is not named" 'has "codex  ✗ review failed @56d1b7b · comment" && ! has "usage limit"'
use failed-stale-limit; run 42 -R acme/webapp --need codex
check "a usage-limit comment from before HEAD does not count" 'has "codex  ✗ review failed @56d1b7b · comment" && ! has "usage limit"'
use failed-older; run 42 -R acme/webapp --need codex
check "a failed review of an older commit: HEAD not reviewed, no findings" 'has "codex  ⧗ HEAD not reviewed — last review @3c1f9e2 failed" && ! has findings'

# (b) wait --trigger asks again once, then waits for the retry
use failed; run wait 42 -R acme/webapp --need codex --trigger --dry-run --timeout 2s --interval 1
want='dry-run: would comment "@codex review" on acme/webapp#42'
check "--trigger --dry-run: prints the @codex review it would post, posts nothing" 'has "$want" && [ "$(comments)" = 0 ]'
use failed; FAKE_THEN="failed-asked running clean" run wait 42 -R acme/webapp --need codex --trigger --timeout 12s --interval 1
check "--trigger: posts @codex review once, waits through the retry, exits 0 on CLEAN" \
  '[ $rc -eq 0 ] && [ "$(comments)" = 1 ] && grep -q -- "--body @codex review" "$FAKE/comments.log" && has "codex failed on HEAD, retry requested" && has "verdict CLEAN"'
use failed-asked; run 42 -R acme/webapp --need codex
check "a request after the failure: status says the retry is requested" 'has "codex  ✗ review failed @56d1b7b (usage limit) · retry requested"'
run wait 42 -R acme/webapp --need codex --trigger --timeout 2s --interval 1
check "a request after the failure counts as requested: no new comment, wait keeps waiting" \
  '[ $rc -eq 2 ] && [ "$(comments)" = 0 ] && has "x timed out after 2s: codex failed on HEAD, retry requested"'
use failed-nolimit; FAKE_THEN="late-limit running clean" run wait 42 -R acme/webapp --need codex --trigger --timeout 12s --interval 1
check "a usage-limit comment that lands after the retry is not a new failure" '[ $rc -eq 0 ] && [ "$(comments)" = 1 ] && has "verdict CLEAN"'
use failed-nolimit; FAKE_THEN="same-second running clean" run wait 42 -R acme/webapp --need codex --trigger --timeout 12s --interval 1
check "a retry in the same second as the failure counts as after it" '[ $rc -eq 0 ] && [ "$(comments)" = 1 ] && has "verdict CLEAN"'

# (c) Codex fails again after a request for HEAD: no point in waiting out the timeout
want='x codex review failed on HEAD 56d1b7b (usage limit) after "@codex review"; retry later: comment "@codex review" again'
use failed; FAKE_THEN="failed-asked failed-again" run wait 42 -R acme/webapp --need codex --trigger --timeout 12s --interval 1
check "failed again after the request: wait exits 2 at once, one comment posted" '[ $rc -eq 2 ] && [ $took -lt 6 ] && [ "$(comments)" = 1 ] && has "$want"'
use failed-again; run wait 42 -R acme/webapp --need codex --trigger --timeout 12s --interval 1
check "already failed after a request: wait --trigger posts nothing, exits 2 at once" '[ $rc -eq 2 ] && [ $took -lt 6 ] && [ "$(comments)" = 0 ] && has "$want"'
run wait 42 -R acme/webapp --need codex --timeout 12s --interval 1
check "already failed after a request: wait without --trigger exits 2 at once" '[ $rc -eq 2 ] && [ $took -lt 6 ] && has "$want"'
run 42 -R acme/webapp --need codex --json
q='.codex.status == "failed" and (.codex.retry_requested | not) and .trigger_candidates == [] and (.stalled | length) == 1 and .verdict == "PENDING"'
check "already failed after a request: --json lists codex as stalled" 'json "$q"'

# (d) regressions: completed and running reviews read as before
use clean; run 42 -R acme/webapp --need codex
check "completed clean: verdict CLEAN" 'has "codex  ✓ clean @56d1b7b · PR opened" && has "verdict CLEAN"'
run wait 42 -R acme/webapp --need codex --trigger --timeout 12s --interval 1
check "completed clean: wait exits 0 and posts nothing" '[ $rc -eq 0 ] && [ "$(comments)" = 0 ]'
use findings; run 42 -R acme/webapp --need codex
check "completed with findings: the finding and verdict FIX" \
  'has "codex  ✗ 1 finding(s) @56d1b7b (P2×1) · PR opened" && has "P2 src/auth/session.ts:51  Expire refresh tokens on logout" && has "verdict FIX — codex P2 src/auth/session.ts:51"'
run wait 42 -R acme/webapp --need codex --timeout 12s --interval 1
check "completed with findings: wait exits 1" '[ $rc -eq 1 ]'
use findings-unlisted; run 42 -R acme/webapp --need codex
check "completed with findings past the last 50 threads: still reported" 'has "codex  ✗ findings @56d1b7b, not among the last 50 threads"'
use running; run 42 -R acme/webapp --need codex
check "running on HEAD: shown as running" 'has "codex  … running @56d1b7b (HEAD)"'
run wait 42 -R acme/webapp --need codex --trigger --timeout 2s --interval 1
check "running on HEAD: wait keeps waiting, posts nothing, exits 2 at the timeout" '[ $rc -eq 2 ] && [ "$(comments)" = 0 ] && has "x timed out after 2s: codex running@56d1b7b"'
use pushed; run wait 42 -R acme/webapp --need sar --timeout 12s --interval 1
want='x sar has not started on HEAD 56d1b7b and will not without a trigger; re-run with --trigger (or comment "@architect-run")'
check "no SAR on a pushed HEAD: wait without --trigger exits 2 at once, as before" '[ $rc -eq 2 ] && [ $took -lt 6 ] && has "$want"'

# prland merges only on CLEAN from `prbots status --json`: a failed review must never pass
use failed; land 42 -R acme/webapp --need codex --dry-run
check "prland: a failed review does not pass the gate" '[ $rc -eq 1 ] && has "gate     PENDING" && ! has "would run" && [ ! -e "$FAKE/merge.log" ]'
use clean; land 42 -R acme/webapp --need codex --dry-run
check "prland: the same PR passes once Codex completes clean (control)" '[ $rc -eq 0 ] && has "gate     CLEAN" && has "would run: gh pr merge" && [ ! -e "$FAKE/merge.log" ]'

echo "$pass passed, $fail failed"
rm -rf "$T"
[ "$fail" -eq 0 ]
