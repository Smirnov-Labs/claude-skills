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

Run it from any checkout of the repo: the main one or the PR's worktree. `prland` is on PATH where skillsync installed this skill; otherwise run `bin/prland` from this skill's base directory. It calls `prbots` from the watching-pr-bot-reviews skill.

| Case | Command |
|---|---|
| A clean PR | `prland 123` |
| The bots this repo requires | `prland 123 --need sar` |
| A repo with no review bots | `prland 123 --need ci` |
| See the plan first | `prland 123 --dry-run` |
| Keep the worktree | `prland 123 --keep-worktree` |

`prland --help` lists the rest (`-R`, `--method`, `--subject`, `--no-sync`).

## Read the output

It prints one line per step:

```
gate     CLEAN @85c6e8f (prbots --need sar)
merge    squash · codex-review: one command for a read-only Codex review (#20)
merged   4af28c7a2c
worktree removed /tmp/wt-codex-review
branch   deleted codex-review (was 85c6e8f1a2)
sync     ~/src/claude-skills is at 4af28c7 (main)
```

| Exit | Meaning |
|---|---|
| 0 | Merged. A cleanup step it skipped says why. |
| 1 | The gate said no (not CLEAN, a draft, closed). Nothing was merged. |
| 2 | The merge failed, or GitHub did not report MERGED. |
| 3 | Usage error. |

Report the merge SHA, plus anything it left in place and why.

## What it will not do

- Merge without a CLEAN verdict, merge a draft, or merge a head that moved after the check (`--match-head-commit`).
- Remove a worktree with `--force`, or one with uncommitted or untracked files, or one with commits past the PR head.
- Touch any branch or worktree except the PR's own. It matches nothing by pattern.
- Switch branches in the main checkout, or sync it while it has tracked changes.
