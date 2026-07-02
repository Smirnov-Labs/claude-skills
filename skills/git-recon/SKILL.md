---
name: git-recon
description: Use when the user wants a git-history health check of an unfamiliar or inherited repository — triggers on "git recon", "codebase health check", "analyze this repo's history", "where are the landmines", or onboarding/due-diligence framing. Do NOT use for architecture review, bug-fixing, or feature work; this skill reads history, not code. Main-thread only — subagents dispatched to execute a delegated task must NOT invoke this skill.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific delegated task, do NOT follow this skill — skip it and return to the task you were given.
</SUBAGENT-STOP>

# Git Recon

Before reading code, read the git history. Five commands reveal where risk concentrates, who owns what, and whether the team is shipping or firefighting. Based on Piechowski's "5 git commands before reading code" (https://piechowski.io/post/git-commands-before-reading-code/).

## When to Use

- Onboarding to an unfamiliar or inherited codebase
- Due diligence on an acquisition or handoff
- Planning a refactor and needing to locate risk
- User asks "what's the state of this repo?" or "where are the landmines?"

## Prerequisites

Run from inside a git repository on the branch the user cares about (usually default). If any check fails, stop and ask the user.

```bash
git rev-parse --is-inside-work-tree   # must print true
git rev-parse --is-shallow-repository  # must print false — shallow clones distort all probes
git rev-parse --abbrev-ref HEAD        # confirm branch scope in the report
```

**Horizon:** all probes use a single 12-month window for comparability. If the user wants a different window, override `SINCE` everywhere, don't mix.

```bash
SINCE="1 year ago"
```

## Pipeline

Run all five probes (in parallel when possible), then synthesize. Do **not** just dump command output — the value is in the cross-referencing.

### 1. High-Churn Files — where change concentrates

```bash
git log --no-merges --since="$SINCE" --format=format: --name-only \
  | grep -v '^$' \
  | sort | uniq -c | sort -nr | head -20
```

Top 20 most-modified files in the last 12 months. Files that change constantly are risky: unpredictable blast radius, likely god-objects or missing abstractions.

**Caveat — renames:** this command is not rename-aware. A file renamed mid-window splits its churn across old and new paths. When drilling into a specific top file, rerun with `git log --follow --no-merges --since="$SINCE" -- <path>` to see true lifetime churn.

**Caveat — generated/vendored files:** lockfiles (`package-lock.json`, `yarn.lock`, `Cargo.lock`), vendored dirs (`vendor/`, `node_modules/`), and generated code will dominate this list and are usually noise. Filter them out before reporting, or flag explicitly.

### 2. Contributor Distribution — bus factor

```bash
git log --no-merges --since="$SINCE" --format='%aN' | sort | uniq -c | sort -rn
```

Who writes the code. One person at 60%+ of commits = dependency risk, especially if they've gone quiet recently.

**Note:** use `git log | sort | uniq -c` instead of `git shortlog -sn`. `git shortlog` reads from stdin when not attached to a TTY, so it silently produces no output in non-interactive shells (CI, tool calls).

**Caveat — commit count ≠ ownership.** In monorepos and bot-heavy repos (Dependabot, renovate) this misleads. For each top risky *directory* from probe 1, rerun scoped ownership:

```bash
git log --no-merges --since="$SINCE" --format='%aN' -- <dir> | sort | uniq -c | sort -rn
```

Also spot-check activity: `git log --author="X" --since="6 months ago" --oneline | wc -l`.

### 3. Bug Hotspots — where problems cluster

```bash
git log --no-merges -i -E --grep="fix|bug|broken|hotfix|regression" \
  --since="$SINCE" --name-only --format='' \
  | grep -v '^$' \
  | sort | uniq -c | sort -nr | head -20
```

Files repeatedly touched by bugfix commits. **Intersect with the churn list (probe 1)** — files appearing on both are the highest-risk code.

**Caveat — keyword false positives:** `fix` matches `prefix`, `suffix`, `fixup!`. `bug` can match `debug`. Treat the list as a starting point; skim a few commit messages to sanity-check before calling a file a hotspot.

### 4. Velocity Trends — shipping cadence

```bash
git log --no-merges --since="3 years ago" \
  --format='%ad' --date=format:'%Y-%m' \
  | sort | uniq -c
```

Commits per month over 3 years (longer window needed to see trend). Report using a **3-month moving average** for the last 12 months vs the prior 12 — not raw month-by-month, which is too noisy. Look for: declining trend (momentum loss), monthly spikes (release batching, not CD), long gaps (project stalls).

### 5. Firefighting Patterns — deploy trust

```bash
git log --oneline --since="$SINCE" \
  | grep -icE 'revert|hotfix|emergency|rollback'
```

Count of reverts/hotfixes in the window. Rule of thumb: **< 6/year normal; > 1/month is a reliability smell**. Follow up with the actual list (drop `-c`) to read the messages — clustered reverts in one week point to a specific bad release worth investigating.

## Optional Drill-Downs

When the top-line report surfaces something interesting, these probes add disproportionate value:

- **Co-change coupling** — files frequently committed together reveal hidden dependencies. For each top hotspot, list the files most often changed in the same commit: `git log --no-merges --since="$SINCE" --name-only --format='---' -- <file> | awk 'BEGIN{RS="---"} {for(i=1;i<=NF;i++)print $i}' | sort | uniq -c | sort -nr | head -10`.
- **Stale branches** — `git for-each-ref --sort=-committerdate --format='%(committerdate:short) %(refname:short)' refs/remotes | head -20`. Long-lived divergent branches = integration risk.
- **Directory-level heatmap** — aggregate probe 1 to directory depth 2 to see which *areas* (not just files) are hot.

## Synthesis

After running all five, produce a **Codebase Recon Report** with these sections. Be explicit about method — don't just eyeball:

1. **Scope** — one line: branch, window, repo size (`git rev-list --count HEAD`), whether generated files were filtered.
2. **Risk Files** — the *set intersection* of probes 1 and 3 (same 12-month window). Name each file, its churn rank, its bug-hotspot rank, and one-line suspicion. These deserve the most careful reading.
3. **Bus Factor** — top 3 contributors with % of total commits in window. Flag if #1 owns > 50%. For each, quote commits in the last 6 months as an activity check.
4. **Momentum** — 3-month moving average of commits/month for the last 12 months vs the prior 12. Call it "rising / flat / declining" with the numbers that support it.
5. **Deploy Health** — revert/hotfix count in the window + verdict against the rule of thumb (< 6/yr normal, > 1/mo smell). If clustered, name the week.
6. **Where to Start Reading** — 3–5 specific files, each with one-line reasoning grounded in the probes above ("churn #2 + hotspot #4, owned 80% by inactive author").

Keep the report under one screen. Lead with Risk Files — that's the payoff.

## Red Flags in the Output

| Signal | What it probably means |
|--------|------------------------|
| One file with 10× the churn of #2 | God object or dumping-ground config |
| Top contributor inactive 6+ months | Knowledge has already left the building |
| Velocity halved in last quarter | Project stalling or team reorg |
| Reverts clustered in one week | A bad release — read those commits |
| Bug hotspots all in one directory | Architectural weak spot, not scattered bugs |

## Anti-Patterns

- **Don't** paste raw command output as the final answer. Synthesize.
- **Don't** run on a shallow clone — results will be misleading. The prerequisite check guards this; don't skip it.
- **Don't** run from a feature branch without saying so. State the branch in the report's Scope section.
- **Don't** include generated files, lockfiles, or vendored dirs in the risk list without flagging them — they'll dominate churn and tell you nothing useful.
- **Don't** skip the intersection step. Churn alone or bugs alone is weaker signal than both together.
- **Don't** trust the bug-keyword grep blindly — `prefix`/`fixup`/`debug` create false positives. Spot-check commit messages before naming hotspots.
- **Don't** mix time windows across probes. One horizon, stated up front.
- **Don't** run on a tiny repo without caveats. Below ~50 commits or 3 contributors, the probes give false precision — report the signals but flag the sample size up front. The skill is designed for mature inherited codebases, not greenfield projects.
