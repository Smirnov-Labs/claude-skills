---
name: pr-land
description: Use when asked to merge or land a pull request ("merge it", "land it", "ship it", "merge when clean"), or to clean up the worktree and branch of a PR that is already merged.
---

# Land a PR

`prland` merges a PR only when its bots are clean, and it confirms that GitHub says MERGED. Then it removes that PR's own worktree and branch, and fast-forwards the main checkout. Done by hand, most sessions stopped after the merge and left the cleanup behind.

## Before you run it

1. Wait for the bots: `prbots wait <PR> --trigger`, in the background (the watching-pr-bot-reviews skill). prland checks the verdict once and does not wait.
2. Read the repo's CLAUDE.md. It may name the bots that must be clean (`--need`) or a merge method other than squash.
3. If this session entered the PR's worktree with EnterWorktree, leave it with ExitWorktree first. Otherwise the harness blocks git in the main checkout.
4. Make sure no agent you started still works in that worktree.

## Run it

Run it from any checkout of the repo: the main one or the PR's worktree. `prland` is on PATH where skillsync installed this skill. Otherwise call it by its full path, `<this skill's base directory>/bin/prland`, and stay in the checkout: it finds the repo and the worktrees from there. It calls `prbots` from the watching-pr-bot-reviews skill.

| Case | Command |
|---|---|
| A clean PR | `prland 123` |
| The bots this repo requires | `prland 123 --need sar` |
| A repo with no review bots | `prland 123 --need ci` |
| See the plan first | `prland 123 --dry-run` |
| Keep the worktree | `prland 123 --keep-worktree` |
| A worktree holds only ignored files you can lose | `prland 123 --allow-ignored` |

A PR URL works too, and names its own repo. `prland --help` lists the rest (`-R`, `--method`, `--subject`, `--no-sync`).

## Read the output

It prints one line per step:

```
gate     CLEAN @85c6e8f (--need sar)
merge    squash · codex-review: one command for a read-only Codex review (#20)
merged   4af28c7a2c
remote   deleted codex-review (was 85c6e8f)
worktree removed /tmp/wt-codex-review
branch   deleted codex-review (was 85c6e8f1a2)
sync     ~/src/claude-skills is at 4af28c7 (origin/main)
```

| Exit | Meaning |
|---|---|
| 0 | Merged. A cleanup step it skipped says why. |
| 1 | The gate said no (not CLEAN, a draft, closed). Nothing was merged. |
| 2 | The merge failed, or GitHub did not report MERGED. |
| 3 | Usage error. |

Report the merge SHA, plus anything it left in place and why.

## What it will not do

- Merge without a CLEAN verdict for this repo, this PR and its current head SHA. It reads `prbots --json`, so text in a check name cannot fake the verdict. A misspelled `--need` is an error, not an empty gate.
- Merge a draft, or a head that moved after the check (`--match-head-commit`).
- Delete the remote branch if someone pushed to it after the merge. The delete carries a lease on the PR head.
- Remove a worktree with `--force`, or one with changed tracked files, untracked files, commits past the PR head, or ignored files other than build and cache output (`.env` and notes stay). It reads these with `git ls-files`, so `status.showUntrackedFiles` cannot hide them.
- Delete a local branch that moved: the delete is an atomic `update-ref` on the PR head.
- Prune other worktrees, or touch any branch except the PR's own. A fork PR's branches are left alone.
- Switch branches in the main checkout, sync it while it has tracked changes, or follow its upstream: it fast-forwards to `origin/<base>`.
