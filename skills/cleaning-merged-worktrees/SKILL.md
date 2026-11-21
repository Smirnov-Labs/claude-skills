---
name: cleaning-merged-worktrees
description: Use when clearing out git worktrees whose pull request has merged, checking which worktrees are safe to delete, or setting up a weekly Orca cleanup automation, before removing worktrees by hand.
---

# Clean merged worktrees

`wtclean` removes linked git worktrees whose pull request merged and that hold nothing local. It decides what is safe to remove, not you. Run it instead of removing a worktree by hand, and read its report. Leave every worktree it keeps, unless the owner asks you to remove one.

## Run it

`wtclean` is on PATH where skillsync installed this skill. Otherwise call it by its full path, `<this skill's base directory>/bin/wtclean`. It needs `gh`, signed in to GitHub. It adds `~/.local/bin` to PATH, so it finds `gh` there under an Orca server too.

| Command | What it does | Exit codes |
|---|---|---|
| `wtclean` | Dry run. Prints what it would remove and what it keeps, with reasons. Changes nothing. | 0 done, 2 one or more errors, 3 usage |
| `wtclean --apply` | Removes, then prints the same report with what happened. | 0 done, 2 one or more errors, 3 usage |
| `wtclean --check` | For the precheck. Prints one line of counts. | 0 if something can go or something failed, 1 if there is nothing to do |

To clear out merged worktrees, run `wtclean`, read the report, then run `wtclean --apply`. `--apply` can take minutes, so run it with a long timeout or in the background. `--repo <path>` (repeatable) adds repos to the scan. Any checkout of a repository works as the path. A usage error prints `wtclean: usage error: <message>` to stderr and exits 3 in every mode, `--check` included.

wtclean scans the git repositories that Orca lists on this host, plus each `--repo`. It runs the Orca CLI in `ORCA_CLI_COMMAND`, else `orca-ide` on PATH. If neither exists but Orca looks installed, it stops with an error. Orca looks installed when `ORCA_USER_DATA_PATH` is set or `~/.config/orca` exists. Without Orca, it scans each `--repo`, or else the repository it runs in.

## The six conditions

A linked worktree goes only when all six hold. The main checkout never goes.

1. It has a branch, is not locked, and is not an agent worktree (an `agent-*` directory or a `worktree-agent-*` branch).
2. GitHub has a merged pull request from that branch into the same repository, and no open one.
3. HEAD is that pull request's head commit or an ancestor of it, so every commit is on GitHub.
4. It holds nothing local: no changed tracked file, no untracked file, no ignored file except build output.
5. Nothing uses it: no Orca agent or terminal, no child workspace with an agent, no process working inside it.
6. Nobody touched it for 24 hours: its git index and HEAD log are more than a day old.

An initialized submodule keeps a worktree, because git will not remove one without `--force`. So does a sparse checkout, because its skip-worktree entries count as local files. Orca listing the worktree twice keeps it too, and so does a child workspace that Orca does not list. Another checkout or an Orca workspace inside the worktree keeps it too, because removing the worktree deletes it. The checkout can belong to any scanned repository, and the workspace can be idle. A folder above the worktree does not count. A problem with one worktree is a reason to keep it, not an error.

For each worktree that can go, `--apply` does this:

1. It checks conditions 4 to 6 again, and what lies inside the worktree. A worktree that fails the check stays.
2. It removes the worktree with Orca's `worktree rm` if Orca lists it, and with `git worktree remove` if not. A worktree that git refuses to remove stays.
3. It deletes the local branch, but only when the branch is at the PR head and no other worktree has it checked out.

Orca's `worktree rm` answers only after the directory and git's entry are gone, and wtclean checks both anyway. Orca leaves the child workspaces of a removed parent in place, and they become top-level workspaces.

## What it never does

- Use `--force`. Neither `git worktree remove` nor Orca's `worktree rm` gets it.
- Run `git worktree prune`.
- Delete a remote branch.
- Delete a local branch that is not at the PR head.
- Remove an `agent-*` or `worktree-agent-*` worktree.
- Remove a main checkout.

## Read the report

Each repository gets a `repo` line, then its worktrees. The `would remove` and `removed` lines come first, then the `kept` lines. wtclean prints each `would remove` and `removed` line at once, and the `kept` lines when it finishes the repository. A run that stops early still shows what it removed.

```text
skip  <path>: not a git repository
repo <main checkout> (<owner/repo> | no GitHub remote)
  would remove  <path>  <branch>  #<n>
  removed       <path>  <branch>  #<n>; <what became of the branch>
  kept          <path>  <branch>: <reason>[ (merged #<n>)]
  error         <where>: <message>
wtclean: <n> to remove, <k> kept (<m> merged), <e> errors
```

- `skip` names an Orca repository that is missing or bare. It is not an error.
- `(no GitHub remote)` on a `repo` line means that its `origin` is not on GitHub. Every worktree there stays.
- `would remove` appears in a dry run. `removed` appears after `--apply`.
- `(merged #<n>)` ends a `kept` line when the branch has a merged PR. Something else keeps the worktree, so read the reason.
- `error` is a failure of `gh`, the Orca CLI, `git worktree list` or wtclean itself. `<where>` is the repository that wtclean was scanning, or `wtclean` when the failure came first. It never names the worktree. The run stops there, and the report still lists the removals that came before.
- The last line counts the run. A dry run says `<n> to remove`, and `--apply` says `<n> removed`. `<m> merged` counts the kept worktrees that have a merged PR.
- `--check` prints only `wtclean: <n> can go, <e> errors`.

A `removed` line ends with what became of the local branch:

- `deleted branch <b> (was <sha>)`: the branch was at the PR head.
- `branch <b> was already deleted`: the branch was gone after the removal. Orca's `worktree rm` can delete a merged branch itself.
- `kept branch <b>: another worktree has it checked out`.
- `kept branch <b>: it is at <sha>, not the PR head <sha>`.
- `kept branch <b>: <git's message>`: git refused to delete it.

A `kept` line gives one reason. The first failing check names it, in this order:

| Reason | What it means |
|---|---|
| `directory missing` | git lists the worktree, but its folder is gone. wtclean never prunes. `git worktree prune` drops the entry. |
| `detached or locked` | It has a detached HEAD, or a lock. |
| `agent worktree (agent-* or worktree-agent-*)` | The name marks it as an agent's worktree. |
| `git cannot read it` | `git rev-parse HEAD` fails in it. |
| `no GitHub remote` | The repository's `origin` is missing or is not on github.com. |
| `too many pull requests from this branch to check them all` | `gh pr list` gave 100 PRs for the branch, its limit, so the list can leave out an open one. |
| `open pull request #<n>` | The branch has an open PR. |
| `no merged pull request` | GitHub has no merged PR from this branch into this repository. A fork PR does not count. |
| `commits not in the pull request` | HEAD holds a commit that no merged PR from this branch holds. |
| `another checkout lies inside it: <path>` | The main checkout or a linked worktree of a scanned repository is inside this worktree. Removing this worktree deletes it. |
| `an Orca workspace lies inside it: <path>` | Orca lists a workspace inside this worktree, whether or not it is in use. Removing this worktree deletes it. |
| `local files: ...` | Condition 4 fails. The rest says why: `<n> changed tracked files`, `<n> untracked files`, `ignored files that are not build output: <names>`, `<n> tracked files are marked assume-unchanged or skip-worktree, so status cannot vouch for them`, `git could not inspect it` or `git could not read its index flags`. |
| `initialized submodules` | It holds an initialized submodule. |
| `Orca lists it more than once` | Orca's list holds the same path twice, so wtclean doubts Orca's view of it. |
| `in use: ...` | Condition 5 fails. The rest says what uses it: `<n> agents in Orca` (any state), `<n> live terminals`, `terminals Orca cannot verify`, `a terminal is attached`, `a child workspace has an agent`, `a child workspace Orca did not list` or `process <pid> (<name>) works in it`. |
| `touched in the last 24 hours` | Condition 6 fails. |
| `git refused the removal: ...` | `--apply` only. git refused, or exited 0 and left the directory in place. The worktree stays. |

Tell the user what wtclean removed, and why it kept each worktree that has a merged PR. Do not clear a reason yourself by discarding files or stopping an agent. Ask the owner.

## Weekly Orca automation

An Orca automation can run `wtclean --apply` each week and post the result as a workspace comment. The run needs a folder workspace: a plain folder that Orca lists as a workspace, not a git worktree. Add one to Orca first. Its sidebar comment shows the last result, and `<dir>` below is its path.

Give the automation this prompt:

```text
Weekly worktree cleanup on this host. Do exactly these steps, then stop.

1. Run "$HOME/.local/bin/wtclean" --apply once, with a 10-minute timeout. Keep its full output and its exit status. If the command is missing or does not start, use exit status 127 and its error as the output. If the timeout stops it, treat that as a nonzero exit status.
2. Set this workspace's comment to one line. If wtclean printed its last line ("wtclean: R removed, K kept (M merged), E errors"), run: "$ORCA_CLI_COMMAND" worktree set --worktree current --comment "wtclean <today, YYYY-MM-DD>: R removed, M merged kept, E errors" --json. Otherwise use the comment "wtclean <today>: did not finish".
3. If the exit status is not 0, also run: "$ORCA_CLI_COMMAND" worktree set --worktree current --unread --json
4. End with wtclean's full output as your last message.

Do not remove, edit, move, commit or push anything yourself, and run no other commands. wtclean alone decides what is safe to remove.
```

Create the automation with this command. Replace `<dir>` with the folder workspace's path. The prompt holds double quotes, so save it to a file and pass it as `--prompt "$(cat <file>)"`. Where `ORCA_CLI_COMMAND` is set, use `"$ORCA_CLI_COMMAND"` in place of `orca-ide`.

```sh
orca-ide automations create --json --name "Worktree cleanup" \
  --provider claude --extra-agent-args="--model sonnet" \
  --workspace path:<dir> --workspace-mode existing --fresh-session \
  --trigger weekly --day 0 --time 09:00 --timezone America/Denver \
  --precheck '[ "$("$HOME/.local/bin/wtclean" --check 2>&1)" != "wtclean: 0 can go, 0 errors" ]' --precheck-timeout 900 \
  --disabled --prompt "<the prompt above>"
```

`--disabled` creates the automation switched off. Run `wtclean` by hand and read its report, then enable the automation in Orca. Change `--day`, `--time` and `--timezone` to suit.

The precheck runs `wtclean --check` before each run. It skips the run only when the output is exactly `wtclean: 0 can go, 0 errors`. A missing or broken `wtclean` prints something else, so the run still starts and Claude reports the failure.

After a run, the workspace comment reads `wtclean <YYYY-MM-DD>: R removed, M merged kept, E errors`, or `wtclean <YYYY-MM-DD>: did not finish`. A nonzero exit also marks the workspace unread. A week the precheck skips leaves the comment as it was.

## Known gaps

- Ignored files inside `node_modules`, `dist`, `build` and the rest of `prland`'s list of build and cache folders count as build output, and go with the worktree.
- wtclean does not see a checkout of a repository that it does not scan, when that checkout lies inside a worktree's build or cache folder. The checkout goes with the worktree.
- Only the 24-hour check protects a worktree that an idle agent in another workspace used through `git -C`.
- The process check reads `/proc`. Without it (macOS), a worktree that passes the checks before it stops the run with exit 2, so wtclean removes nothing there.
- The process check skips other users' processes, and same-user processes it cannot read.
- The process check compares real paths, so it does not see a process that works in the worktree through a bind mount.
- wtclean ignores fork PRs, so a clone whose `origin` is a fork keeps its worktrees.
- A tool error stops the run at the first error, and wtclean does not scan the worktrees after it.
- `git worktree remove` and Orca's `worktree rm` get 10 minutes, and every other call gets 2 minutes. A removal that times out stops the run, and can leave a half-deleted worktree. If tracked files are gone, later runs keep it until someone cleans it up by hand.
- A sidebar comment whose date stops advancing means the weekly run did not finish, or the precheck skipped it because nothing could go. Check `automations runs --id <automation-id>`. A skipped week shows as `skipped_precheck`.
