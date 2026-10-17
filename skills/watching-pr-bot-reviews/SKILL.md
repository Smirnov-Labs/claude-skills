---
name: watching-pr-bot-reviews
description: Use when waiting for, polling, reading, or reporting the automated reviewers on a GitHub PR — Codex (chatgpt-codex-connector) and the Architecture Review / SAR action (github-actions[bot]), plus CI — after opening a PR, after pushing to one, before merging or declaring a PR done, or when asked "what did the bots say". Also use the moment you are about to write a sleep/until loop or a wait-*.sh / poll_*.sh script around `gh api` or `gh pr view`, and when orchestrating subagents that open PRs. Provides `prbots wait` (blocks until the bots have reported on the PR's HEAD commit; run it in the background) and `prbots` (one-shot digest + CLEAN/FIX/BLOCK/PENDING verdict).
---

# Watching PR bot reviews

**Never hand-roll a poller for PR bots** — no `until gh api …; do sleep 30; done`, no
`wait-codex.sh`. A 2026-10-16 transcript audit found 365 such waits across ~30 sessions
(~800K output tokens, ~133M context tokens re-read), re-written after every push, keyed on
five different "done" signals — and three PRs merged code Codex never reviewed.
Use `prbots`, which ships in this skill's `bin/` and is on PATH wherever skillsync installed
it (otherwise run `bin/prbots` from this skill's base directory).

| Situation | Run | How |
|---|---|---|
| Just opened the PR | `prbots wait <PR>` | Bash `run_in_background: true` |
| Just pushed to an open PR | `prbots wait <PR> --trigger` | Bash `run_in_background: true` |
| "What did the bots say?" / before merging | `prbots <PR>` | foreground, ~6-line digest |

`<PR>` = number or PR URL (default: the current branch's PR); add `-R owner/repo` when cwd
isn't the repo. After starting a background `wait`, **do not poll it** — no sleep, no tailing
its output, no re-checking with `gh`. You are notified when it exits; its output is the digest.

This skill reads and waits; it never commits or pushes. To drive a PR to clean (fix → push →
wait, repeated), the user runs `/pr-fix`.

## Why `--trigger` after a push

Neither bot re-reviews a push by itself: Codex runs on PR open / ready-for-review / an
`@codex review` comment; the SAR on open / ready-for-review / an `@architect-run` comment,
never on push. `--trigger` posts those comments once per HEAD, only when no review of HEAD
is running or already requested. Without it, `wait` exits 2 within ~75s once it is clear no
review will start, instead of sitting out the timeout. If your checkout is the pushed PR
branch, `wait` first waits for GitHub to show that SHA, so a wait started right after
`git push` never reads the previous commit's review.

## Reading the result

```
PR #42 · acme/webapp · fix/session-timeout · HEAD 56d1b7b · OPEN
codex  ✗ 1 finding(s) @56d1b7b (P2×1) · PR opened
         P2 src/auth/session.ts:51  Expire refresh tokens on logout
sar    ✓ No issues found · severity 0/4 · blockers false · 01:22Z
ci     · no checks
verdict FIX — codex P2 src/auth/session.ts:51
```

| verdict (wait exit) | meaning | do |
|---|---|---|
| CLEAN (0) | every needed bot reviewed HEAD, nothing open | may merge; show the digest to the user |
| FIX (1) | open P2 / SAR advisory | fix, or reply on the thread with the reason; then push + `wait --trigger` |
| BLOCK (1) | open P0/P1, SAR blockers or severity ≥3, CI failure | must fix (or reply with the reason) before merging |
| PENDING (2) | a needed bot hasn't reviewed HEAD | read the `x …` line: timed out / needs `--trigger` / PR head not updated. **Never merge on PENDING** |

A finding is handled once its thread is resolved or has a non-bot reply (shown `[replied]` /
`[resolved]`). Don't declare a PR done without showing the user the digest, even when it is
CLEAN. `--full` adds finding bodies + the full SAR; `--json` emits the machine payload.
`status` always exits 0; errors exit 3. Other flags: `--need codex,sar,ci|all`
(default codex, + sar if the repo has an architecture-review workflow; `status` adds ci),
`--timeout 30m`, `--interval 30` (one GraphQL call per poll), `--sha SHA`, `--dry-run`
(print trigger comments instead of posting).

## Orchestrating subagents

Don't paste a polling recipe into subagent prompts. On 2026-10-16 one did
(`… | grep -q Completed`, which also matches the *previous* commit's review) and each of its
13 subagents then wrote its own `wait-codex.sh`. Give them one line instead:

> Wait for the PR bots with `prbots wait <N> -R <repo> --trigger` (Bash run_in_background);
> merge only on CLEAN, or after addressing FIX/BLOCK — never on PENDING.

## Signals (if you must reason by hand — prbots already does this)

- **Codex**: one summary comment, edited in place, embeds
  `<!-- codex-review-state:v1 {"code_review":{"commit_sha":…,"status":"running"|"completed","has_any_findings":…,"has_unresolved_findings":…}} -->`.
  Done for HEAD ⇔ `commit_sha == HEAD && status == completed`. Findings = review threads tagged
  `codex-code-review-finding` with a `P0`–`P3` badge; a clean run posts a "Didn't find any
  major issues" receipt + 👍.
- **SAR**: `github-actions[bot]` comment `## ✅|⚠️|🚫|🟢 Architecture Review - <verdict>` with
  `**Severity**: N/4 | **Blockers**: bool`. Fresh only if posted after HEAD's commit / force-push.
- **Where they live (REST)**: Codex findings in `pulls/<PR>/comments`, its formal review in
  `pulls/<PR>/reviews`; its summary comment and the SAR both in `issues/<PR>/comments`.
- **Logins**: REST = `chatgpt-codex-connector[bot]` / `github-actions[bot]`; GraphQL and
  `gh pr view --json comments` = `chatgpt-codex-connector` / `github-actions` (no `[bot]`).
  `gh pr view` *does* include both bots — a filter that expects the `[bot]` suffix there
  matches nothing, which makes it look as if the bots never commented.

## Limits

SHA-strict: a clean rebase also reads as "HEAD not reviewed" — re-trigger, or judge it and
say so. Reads the last 50 review threads.
