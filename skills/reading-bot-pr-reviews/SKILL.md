---
name: reading-bot-pr-reviews
description: Use when reading or reporting what automated PR reviewers left before merging — Codex (`chatgpt-codex-connector`) and an Architecture-Review / SAR GitHub Action (`github-actions[bot]`). Triggers on "what did the bots say", before declaring a PR done or merging, or when a Codex finding or clean verdict seems missing because `gh pr view --json comments` came back empty. Read-only (does not commit or push); for auto-fixing PR feedback use `/pr-fix` instead.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific delegated task, do NOT follow this skill — skip it and return to the task you were given.
</SUBAGENT-STOP>

# Reading Bot PR Reviews

## Overview

Two automated reviewers post PR feedback through channels the default `gh` query **misses**. Codex (`chatgpt-codex-connector[bot]`) posts to **three** endpoints; an Architecture-Review action posts a **System Architecture Review (SAR)** as a fourth. This skill fetches all four streams, filters on **exact** bot logins, classifies findings by severity, and reports a merge verdict.

**Read-only.** It reads and reports. It never commits or pushes — for an autonomous fix loop use `/pr-fix`.

**Core principle:** `gh pr view --json comments` misses both bots. **A clean Codex verdict AND the SAR both live in *issue* comments, not inline.** Filtering author logins by substring (`codex`, `architect`) misses both — the SAR posts as the generic `github-actions[bot]`. Use exact `[bot]` logins.

## When to Use

- "What did the bots say on PR #N?" — before merging, or before declaring a PR done
- A Codex finding or a clean "no issues" verdict seems missing (the inline endpoint is empty)
- Confirming both reviewers passed before merge

**Not for:** auto-committing fixes to PR feedback (→ `/pr-fix`); sending a *plan* to Codex for review (→ `codex-plan-review`, the reverse direction).

## The Four Streams

| # | Stream | Endpoint | Filter login | What lives here |
|---|--------|----------|--------------|-----------------|
| 1 | Codex inline findings | `pulls/<PR>/comments` | `chatgpt-codex-connector[bot]` | Per-line findings with `P1`/`P2`/`P3` severity badges |
| 2 | Codex formal review | `pulls/<PR>/reviews` | `chatgpt-codex-connector[bot]` | Top-level summary + review `state` (e.g. `CHANGES_REQUESTED`) |
| 3 | Codex run summary | `issues/<PR>/comments` | `chatgpt-codex-connector[bot]` | **Clean "Didn't find any major issues" verdict lives ONLY here** |
| 4 | Architecture SAR | `issues/<PR>/comments` | `github-actions[bot]` | System Architecture Review — severity rating + blocker list |

Streams 3 and 4 hit the **same** endpoint but filter for **different** bots — keep them as two separate queries so neither is lost in the other's output.

## Quick Reference

Derive the PR and repo so this works in any repository (do **not** hardcode):

```bash
PR=${PR:-$(gh pr view --json number -q .number)}   # or set PR=42 explicitly
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

Fetch all four streams (`--paginate` so long threads aren't truncated):

```bash
# 1. Codex inline findings (P1/P2/P3 detail)
gh api repos/$REPO/pulls/$PR/comments --paginate \
  --jq '.[] | select(.user.login=="chatgpt-codex-connector[bot]") | {path, line, body}'

# 2. Codex formal review summary
gh api repos/$REPO/pulls/$PR/reviews --paginate \
  --jq '.[] | select(.user.login=="chatgpt-codex-connector[bot]") | {state, body}'

# 3. Codex run summary (clean verdict lives here)
gh api repos/$REPO/issues/$PR/comments --paginate \
  --jq '.[] | select(.user.login=="chatgpt-codex-connector[bot]") | .body'

# 4. Architecture SAR
gh api repos/$REPO/issues/$PR/comments --paginate \
  --jq '.[] | select(.user.login=="github-actions[bot]") | .body'
```

**Triggering the bots** (if they haven't run yet): comment `@chatgpt-codex-connector review this PR` for Codex; the Architecture-Review action runs automatically on PR `opened`/`ready_for_review`, and `@architect-run` re-triggers it.

```bash
gh pr comment $PR --body "@chatgpt-codex-connector review this PR"
```

Codex takes ~2–3 min; the architecture review ~90s. They can be slower when backed up.

## Classify and Report

Map findings to severity, then emit a single verdict:

- **P0 / P1, or SAR severity ≥ 3, or a `CHANGES_REQUESTED` review** → **BLOCK MERGE**. Must address first.
- **P2 / low-severity SAR notes** → **RECOMMEND FIXES**. Surface each with a fix-now-vs-follow-up call.
- **P3 / "Didn't find any major issues" / SAR severity < 3, no blockers** → **CLEAN**.

Report shape:

```
## Bot Review Summary — PR #<N>

**Codex inline:** <count> (P1: X, P2: Y, P3: Z)  — <path:line + 1-line each>
**Codex review:** <state + body excerpt, or "no formal review">
**Codex run summary:** <body, esp. a clean verdict>
**Architecture SAR:** <severity + blockers, or "no SAR yet">

**Verdict:** BLOCK MERGE | RECOMMEND FIXES | CLEAN
```

## Caveats

- **Re-fetch after every push.** Codex obsoletes its own findings — it updates a single review per push, so old findings are replaced by new commits. Reading stale output is the same as missing it.
- **A force-push / rebase does NOT re-trigger the architecture review** (it fires on `opened`/`ready_for_review`). After a rebase, comment `@architect-run` to refresh the SAR.
- **Empty ≠ clean.** Empty output can mean the bot hasn't finished. Confirm Codex finished via stream 3 (a clean run posts a run-summary comment there) before treating empty streams 1–2 as a pass.
- **Don't declare the PR done without showing the user the output** — even when it's "no findings, verdict CLEAN."

## Common Mistakes

| Mistake | Why it bites | Fix |
|---------|--------------|-----|
| `gh pr view --json comments` | Misses BOTH bots entirely | Hit the four `gh api` endpoints above |
| Substring filter `codex`/`architect` | SAR posts as `github-actions[bot]`; misses it | Filter on exact `[bot]` login |
| Checking only `pulls/<PR>/comments` | Clean Codex verdict + SAR live in `issues/<PR>/comments` | Always read all four streams |
| "Inline is empty, so Codex didn't run" | Clean verdicts post to issue comments | Check stream 3 before concluding |
| Hardcoding the repo | Skill won't travel to other repos | Derive `REPO` via `gh repo view` |
| Not re-fetching after a push | Codex obsoletes findings per push | Re-fetch every round |

## Discovering the SAR bot in an unfamiliar repo

`github-actions[bot]` is the default when the Architecture-Review workflow posts via the built-in `GITHUB_TOKEN` (the common case). If a repo posts its SAR under a custom GitHub App or PAT, list distinct comment authors to find the real login, then swap it into stream 4:

```bash
gh api repos/$REPO/issues/$PR/comments --paginate --jq '.[].user.login' | sort -u
```
