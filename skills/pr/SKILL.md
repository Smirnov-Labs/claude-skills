---
name: pr
description: Use when the user runs /pr to commit the current work, push the branch, and open or update its pull request.
disable-model-invocation: true
argument-hint: "[base branch]"
---

# /pr: commit, push, open or update the PR

The repo's own rules come first. If the repo has `.claude/commands/pr.md`, or a CLAUDE.md with PR rules (a base branch, a title format, an issue link, required checks), read them now. Where they differ from the steps below, follow them.

The base branch is the argument, if the user gave one. Otherwise it is the repo's default branch: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.

## 1. Check where you are

1. Run `git branch --show-current`. If you are on the base branch, stop. Create a branch first, or a worktree if other sessions share this checkout.
2. Run `git status` and `git diff`. Know every change before you stage it.

## 2. Commit

1. Stage the files you mean, by name. In a shared checkout, `git add .` and `git add -A` pick up other sessions' edits.
2. Write the message in the repo's style (`git log --oneline -10`): what changed, and why. End it with the attribution lines your session gives you.
3. Never skip hooks with `--no-verify`.

## 3. Check what the push will carry

```bash
git fetch origin "$BASE"
git log --oneline "origin/$BASE..HEAD"
git diff --name-only "origin/$BASE..HEAD"
```

Only your commits and your files may appear. Anything else means a wrong base: fix that before you push.

If the repo is public, scan the added lines before you push. Look for secrets and private details: tokens, internal hostnames, private IPs, home-directory paths, client names. Scan the commit message too.

## 4. Push

`git push -u origin HEAD`

## 5. Open or update the PR

1. `gh pr view --json number,url` finds an existing PR for this branch. If one exists, update its body with `gh pr edit --body-file FILE`, and say what is new.
2. If none exists, search for a duplicate first: `gh pr list --state all --search "<keywords> in:title"`.
3. Create it: `gh pr create --base "$BASE" --title "..." --body-file FILE`. The body has Summary, Changes and Testing sections, and ends with your session's attribution line.
4. Keep the title and body plain: what changed, why, and how you tested it.

## 6. Then

1. Wait for the reviewers: `prbots wait <PR> --trigger`, in the background (the watching-pr-bot-reviews skill).
2. Fix their findings with /pr-fix.
3. Merge with /pr-land when the PR is clean.
