---
name: pr
description: Use when the user runs /pr to commit the current work, push the branch, and open or update its pull request.
disable-model-invocation: true
argument-hint: "[base branch]"
---

# /pr: commit, push, open or update the PR

The repo's own rules come first. If the repo has `.claude/commands/pr.md`, or a CLAUDE.md with PR rules (a base branch, a title format, an issue link, required checks), read them now. Where they differ from the steps below, follow them.

Find the base branch before anything else:

1. If this branch already has a PR (`gh pr view --json number,url,baseRefName`), its `baseRefName` is the base. If the user named a different base, stop and ask: the PR targets another branch.
2. Otherwise the base is the argument, if the user gave one, or else the repo's default branch: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.

## 1. Check where you are

1. Run `git branch --show-current`. If you are on the base branch, stop. Create a branch first, or a worktree if other sessions share this checkout.
2. Run `git status`, `git diff` and `git diff --cached --stat`. Know every change before you stage it.
3. If the index already holds changes you did not make, stop and ask the user. A commit would take them along, and unstaging them can lose another session's work.

## 2. Commit

1. Stage the files you mean, by name. In a shared checkout, `git add .` and `git add -A` pick up other sessions' edits.
2. Write the message in the repo's style (`git log --oneline -10`): what changed, and why. End it with the attribution lines your session gives you.
3. Never skip hooks with `--no-verify`.

## 3. Check what the push will carry

```bash
git fetch origin "$BASE"
git log --oneline "origin/$BASE..HEAD"        # the commits the push carries
git diff --name-only "origin/$BASE...HEAD"     # the files the PR changes (three dots: since the branch left the base)
```

Only your commits and your files may appear. Anything else means a wrong base: fix that before you push.

If the repo is public, scan the added lines before you push. Look for secrets and private details: tokens, internal hostnames, private IPs, home-directory paths, client names. Scan the commit message too.

## 4. Push

`git push -u origin HEAD`

## 5. Open or update the PR

1. If the branch has a PR (found above), update its body with `gh pr edit --body-file FILE`, and say what is new.
2. If none exists, search for a duplicate first: `gh pr list --state all --search "<keywords> in:title"`.
3. Create it: `gh pr create --base "$BASE" --title "..." --body-file FILE`. The body has Summary, Changes and Testing sections, and ends with your session's attribution line.
4. Keep the title and body plain: what changed, why, and how you tested it.

## 6. Report

Give the user the PR URL and a line on what it holds, then stop. Do more only if the user asked for it:

- wait for the reviewers: `prbots wait <PR> --trigger`, in the background (the watching-pr-bot-reviews skill);
- fix their findings: /pr-fix;
- merge: /pr-land.
