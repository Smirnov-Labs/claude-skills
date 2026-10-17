---
name: pr-fix
description: Use when the user runs /pr-fix or asks to drive an open PR to clean by looping on CI failures and reviewer feedback (Codex, the Architecture Review / SAR, humans) — read, fix, commit, push, wait for the bots, repeat. It commits and pushes on its own, so it runs only on explicit request.
disable-model-invocation: true
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific delegated task, do NOT follow this skill — skip it and return to the task you were given.
</SUBAGENT-STOP>

# PR Fix

You are entering an autonomous loop that drives a pull request to a clean state. Each round: read CI status + all reviewer feedback, fix what's blocking, commit, push, wait for new signal, repeat.

Reading and waiting on the bots goes through `prbots` (from the `watching-pr-bot-reviews` skill: on PATH where skillsync installed it, otherwise that skill's `bin/prbots`). Never write a `sleep` / `until` poller.

## Prerequisites

The current branch MUST have an open PR. Verify with `gh pr view --json number,state,headRefName`. If no PR exists, stop and tell the user to open one first.

## Process

### Step 1: Identify the PR

Capture once and reuse throughout the loop:

```
PR_NUMBER=$(gh pr view --json number -q .number)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
NEED=codex,ci
gh api repos/$REPO/actions/workflows --jq '.workflows[].path' | grep -qi archit && NEED=$NEED,sar
```

`NEED` is what each round waits for: Codex and CI always, the SAR only when the repo has an architecture-review workflow (waiting on a SAR that never runs would sit out the timeout).

### Step 2: Run the Fix Loop

Execute up to **5 iterations**. Each iteration is one full read → fix → push → wait cycle.

#### 2a. Read PR state

1. **Bots and CI, one call:**
   ```
   prbots $PR_NUMBER --need $NEED --full
   ```
   Codex findings, the SAR, CI checks, and a CLEAN / FIX / BLOCK / PENDING verdict for HEAD. For a failing check, fetch its log:
   ```
   gh run view <run-id> --log-failed
   ```

2. **Human feedback** (prbots covers only the bots):
   ```
   gh api repos/$REPO/pulls/$PR_NUMBER/comments --paginate --jq '.[] | select(.user.type != "Bot") | {user: .user.login, path, line, created_at, body}'
   gh api repos/$REPO/pulls/$PR_NUMBER/reviews --paginate --jq '.[] | select(.user.type != "Bot") | {user: .user.login, state, submitted_at, body}'
   gh api repos/$REPO/issues/$PR_NUMBER/comments --paginate --jq '.[] | select(.user.type != "Bot") | {user: .user.login, created_at, body}'
   ```

3. **Last-commit timestamp** — anchor for distinguishing addressed vs. unaddressed human feedback:
   ```
   git log -1 --format=%cI
   ```

#### 2b. Classify the signal

- **Blocking** — everything behind a BLOCK verdict (Codex P0/P1, SAR blockers or severity ≥ 3 of 4, failing CI), a human `CHANGES_REQUESTED` review, human comments flagging correctness/security/architecture. Must fix.
- **Fix or answer** — everything behind a FIX verdict (Codex P2, SAR advisories). Fix it, or reply on the thread with the reason; a non-bot reply marks the finding handled.
- **Nice-to-have** — P3, style nits, optional suggestions. Defer and report at the end.
- **Already addressed** — bot findings prbots shows as `[replied]` / `[resolved]`; human feedback older than the last commit whose diff visibly resolves it. Skip.

A PENDING verdict is not a failure — proceed to 2d (wait).

#### 2c. Apply fixes

For each blocking item:

1. Make the code change.
2. Reference the specific comment/check being addressed in the commit message body.

When all blocking items in this round are fixed, commit and push:

```
git add <files>
git commit -m "$(cat <<'EOF'
fix: address PR feedback (round N)

- [item 1 — link to comment or check]
- [item 2 — link to comment or check]
EOF
)"
git push
```

End the message with whatever attribution trailer your environment asks for.

#### 2d. Wait for new signal

After pushing (or if no fixes were needed because everything is pending), start the wait with Bash `run_in_background: true`:

```
prbots wait $PR_NUMBER --need $NEED --trigger
```

Do not poll it: no `sleep`, no tailing its output, no re-checking with `gh`. You are notified when it exits, and its output is the digest for the next round. `--trigger` matters because neither bot re-reviews a push on its own. Exit codes:

- `0` CLEAN → go to 2e.
- `1` FIX / BLOCK → next iteration.
- `2` PENDING (timed out after 30 min, review never started, or PR closed) → stop and report; read its `x …` line for the reason.
- `3` usage / API error → stop and report.

#### 2e. Exit conditions

Stop the loop when the wait exits `0` (every needed bot reviewed HEAD, CI green, nothing open) **and** no blocking human feedback newer than the most recent commit remains.

If you hit 5 iterations without converging, stop and report the remaining blockers.

**IMPORTANT:** Work silently through iterations — do NOT spam the user with per-round status. Only emit the final summary in Step 3.

### Step 3: Report

After the loop exits, present:

#### Final Status
- **PR:** #$PR_NUMBER ($PR_URL)
- **Outcome:** `clean` | `blocked after N rounds` | `pending: <reason from prbots>`
- **Iterations:** N of 5
- **Final digest:** the last `prbots` output

#### Fixes Applied
- Round 1: [list of commits + what they addressed]
- Round 2: ...

#### Deferred (Nice-to-Haves Not Addressed)
- [suggestion]: [why deferred — usually "non-blocking" or "needs user judgment"]

#### Remaining Blockers (if outcome ≠ clean)
- [item]: [why it couldn't be auto-resolved — e.g., needs human decision, ambiguous, requires infra change]

## Important Notes

- **Bots through prbots, humans through the three `gh api` calls.** prbots reads every bot surface for HEAD; it does not report human comments.
- **Anchor on commit timestamp** to avoid re-fixing already-addressed human feedback in later rounds.
- **Never merge on PENDING.** The SAR scores severity out of 4; 3 or more blocks.
- **Never force-push** unless the user explicitly asks. Normal pushes only.
- **Never skip hooks** (`--no-verify`). If a pre-commit hook fails, fix the underlying issue.
- If feedback is ambiguous or requires a product/architecture decision, defer it and surface in the final report — do not guess.
