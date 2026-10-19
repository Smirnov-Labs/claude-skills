---
description: Project configuration and memory bank system for Claude Code
alwaysApply: true
---

# Project Configuration

This file contains project-specific intelligence and configuration for Claude Code sessions.

## Memory Bank System

This project uses a Memory Bank system to maintain context across sessions. All memory files are stored in `.claude/memory-bank/` and should be read at the start of every conversation.

### Core Memory Files (Read these in order):
1. **memory-rules.md** - System documentation
2. **projectbrief.md** - Foundation document
3. **productContext.md** - Product vision
4. **systemPatterns.md** - Architecture patterns
5. **techContext.md** - Technical setup
6. **activeContext.md** - Current work focus
7. **progress.md** - Status tracking

## Elegance Demand

For non-trivial changes, pause and ask yourself: is there a more elegant solution? If your plan feels hacky, step back and rebuild it properly. Elegant code is simple, clear, and does not fight the architecture.

If you encounter pre-existing issues in code you're touching, be a good citizen and clean them up too. Leave the codebase better than you found it.

## Instructions for Claude

### On Every Session Start:
1. **Read all core memory bank files** in the order listed above
2. Verify understanding of current context
3. Check activeContext.md for immediate priorities
4. Review progress.md to understand what's complete and what's pending

### When User Says "update memory bank":
1. **Review ALL memory bank files** (mandatory - don't skip any)
2. Update files that need changes based on recent work
3. Pay special attention to activeContext.md and progress.md
4. Document any new patterns discovered
5. Update project intelligence in this file if needed

### Planning Mode (via /plan command):
1. Read Memory Bank (automatic)
2. Verify context completeness
3. Ask 4-6 clarifying questions based on findings
4. Draft comprehensive plan
5. Get user approval
6. Implement systematically

## Project Intelligence

This section grows as patterns and preferences are discovered during work on this project.

### Project-Specific Patterns
- How skillsync works, and the shared Codex and PR-bot patterns: see `ARCHITECTURE.md`.

### User Preferences
- The maintainer puts speed and ease of use first, not publishing everything. Generic skills come here. Anything private goes to the maintainer's private skills repo.
- Skills reach machines only through skillsync. Not through dotfiles, and not through `/plugin install` on a machine where `settings.json` is a dotfiles symlink.
- Plain English in anything a reader acts on. Run `python3 skills/de-slopping/ste_lint.py <file>` on PR and commit text, and fix every hard finding.

### Lessons Learned
- A skill that calls a CLI breaks when the CLI changes. codex-cli 0.163 removed `--full-auto`. With `2>/dev/null`, the exit status 2 became an empty result, and the skill carried on without Codex. Keep stderr in a log and check the exit status.
- Pinned model names go stale: `gpt-5.4-codex`, then `gpt-5.5`. Pin with a fallback, and keep a dated table of the models that you tested.
- The Architect-Gate review blocks indirect hints of private work too: "a private repo", the name of a private feature, step numbers from a private plan (#13).

### Known Gotchas
- **The working clone can be live.** On an authoring machine, the skillsync source is a symlink to the working clone. Every Claude Code session on that machine loads the files that are checked out. Never switch branches in that clone. Do PR work in a worktree: `git worktree add -b <branch> /tmp/<dir> origin/main`. Other sessions can have uncommitted edits in the clone. Leave them alone.
- **`prbots` waits for Codex by default**, and Codex is not enabled here. Use `prbots wait <PR> --need sar --trigger`.
- **The review does not run again on push.** `--trigger` or an `@architect-run` comment starts it.

### Effective Approaches
- **Test a skill change like code.** First run the old instructions as written, and watch them fail. Then copy the code blocks out of the new SKILL.md and run them with only the placeholders filled in. (#9 and #15 were tested this way.)
- **Leak-scan before every push.** Run `detect-secrets scan <files>`. Also grep the added lines for client names, internal hostnames, RFC1918 IPs, private repo names, tokens and home-directory paths.
- **After a change to `bin/skillsync`,** run `tests/skillsync.sh`. On macOS, also run it under `/bin/bash` (3.2).
- **Merges:** squash, with a subject that ends in `(#N)`, then delete the branch. Machines pick up main at their next `skillsync`.

---

## Notes

- Memory Bank files are in `.claude/memory-bank/`
- Templates are provided - fill them out based on actual project
- Update frequently to maintain accuracy
- The Memory Bank is the primary context system for this project

## Skills

This repo is **public**, so it only holds skills anyone may read. A skill that mentions clients, internal hosts or IPs, private repos, credentials, or real business data goes in the maintainer's private skills repo instead. The Architect-Gate review blocks such content here (`.github/claude/prompts/02-public-skills-repo.prompt.md`).

How skillsync works, and why it is built that way: `ARCHITECTURE.md`.

### Structure

- **`skills/<name>/`** -- one directory per skill:
  - `SKILL.md` -- YAML frontmatter (`name` matching the directory, and a `description` saying when to use it; new skills start it with "Use when") and the skill prompt
  - supporting reference files
  - `bin/` (optional) -- executables the skill calls. skillsync links them onto PATH, so names must be unique across the repo
  - `UPSTREAM` -- only on vendored third-party skills (source, commit, license). Update them by re-copying from upstream, not by editing
- **`bin/skillsync`** -- symlinks every skill from every skills repo cloned under `~/.local/share/skillsync/` into `~/.claude/skills/`, and every `bin/` executable into `~/.local/bin/`. It must never name a specific repository (that is what keeps private repos private) and must stay compatible with bash 3.2. After changing it, run `tests/skillsync.sh` (sandboxed; it never touches your real directories).
- **`.claude-plugin/marketplace.json`** -- some of the same skills as Claude Code plugins, for people who install with `/plugin`. The maintainer's machines use skillsync instead; listing a new skill here is optional.

### Installing

```bash
git clone -q https://github.com/Smirnov-Labs/claude-skills ~/.local/share/skillsync/claude-skills \
  && ~/.local/share/skillsync/claude-skills/bin/skillsync
```

After that, `skillsync` pulls and relinks, and `skillsync add <git-url>` adds another skills repo (a private one, on machines that can clone it). On an authoring machine, make the source a symlink to your working clone so edits are live: `ln -s <working clone> ~/.local/share/skillsync/claude-skills`.

### Current Skills

| Skill | Purpose |
|-------|---------|
| `presentation-blueprint` | Build pitch/technical/update decks end-to-end (analyze → strategize → outline → style → render) |
| `codex-plan-review` | Send the current plan to Codex (high effort, read-only) for an independent architectural review |
| `detect-overengineering` | Audit a plan document for LLM-style overengineering — rubric pass + Codex adversarial pass + merged findings with proposed edits |
| `git-recon` | 12-month git-history health check — churn, bus factor, bug hotspots, velocity, firefighting |
| `watching-pr-bot-reviews` | Wait for and read the PR bots (Codex, SAR, CI) with `prbots` instead of hand-written pollers |
| `pr-fix` | `/pr-fix`: loop on a PR — fix CI and review feedback, push, wait with `prbots`, repeat until clean (user-invoked only) |
| `bd-to-br-migration` | Migrate docs from bd (beads) to br (beads_rust) |
| `debugging-kubernetes-rollouts` | Debug failed Kubernetes rollouts and ArgoCD / GitOps sync problems |
| `debugging-nodejs-apps` | Systematic debugging of Node.js startup, dependency, and runtime failures |
| `operating-frappe-on-kubernetes` | Operate, upgrade, and debug Frappe / ERPNext on Kubernetes: config on the sites PVC, first-site bootstrap, major-version upgrades, Error Log / email / PDF debugging |
| `hyprland-lua` | Script, control, and debug a Hyprland compositor configured in Lua |
| `quickshell-bar` | Edit and debug a Quickshell (Qt6/QML) status bar on Hyprland |
| `de-slopping` | Cut hedges and filler from written deliverables; bundles a Simplified Technical English linter (`ste_lint.py`) and an optional `slop_guard` Stop hook |
| `minto-pyramid` | Restructure a write-up answer-first (Minto Pyramid) |
| `humanizer` | Remove signs of AI-generated writing (vendored, see `UPSTREAM`) |
| `nonstop` | Autonomous work mode driven by a Stop hook (vendored, see `UPSTREAM` for the hook line) |

### Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter; put reference files and any `bin/` executables alongside.
2. Workflow skills that take over a session get a `<SUBAGENT-STOP>` block right after the frontmatter (see `git-recon`). Leave it off tool and reference skills that subagents are meant to use, such as `watching-pr-bot-reviews`.
3. Run `skillsync link` and check the skill shows up in a new Claude Code session.
4. Open a PR; the Architect-Gate review checks it for private material.

### Project Commands

`.claude/commands/` holds commands that only exist inside this repo: `/pr` (commit, push, create or update a PR), `/plan`, `/loop-review`, `/memory`. Anything meant for every machine belongs in `skills/`, which is why `/pr-fix` moved there.

---

## Architect-Gate: Automated Architecture Review

This project has an automated "Senior Architect in CI" that reviews every PR for architectural consistency and anti-patterns.

**Location**: `.github/claude/` contains prompts and workflow
**Documentation**: See `.github/claude/README.md` for full details

### What It Does
- Runs on every PR automatically
- Reviews changes against Memory Bank and CLAUDE.md
- Checks for 10+ categories of anti-patterns
- Enforces Project-specific architectural invariants
- Posts System Architecture Review (SAR) as PR comment
- Blocks merge if severity ≥ 3 or blockers present

### Rules Enforced

This repo's rules live in `.github/claude/prompts/02-public-skills-repo.prompt.md`:
1. **Nothing private** (blocker): no client names, internal hosts or IPs, private repo names, credentials, or real business data.
2. **Skill layout**: `skills/<name>/SKILL.md` with a matching `name`; `bin/` names unique; `bin/skillsync` names no repository.
3. **Vendored skills**: keep the upstream `LICENSE`; update by re-copying from upstream.

### Testing Locally
```bash
# Test prompt composition
./.github/claude/test-prompt-composition.sh

# Review composed prompt
less .architect-gate-test/full-prompt.md

# Test with ACT (requires ANTHROPIC_API_KEY)
act pull_request -s ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
```

### For PR Authors
- Review SAR comment for specific issues
- Address blocker items before merge
- Push new commits to re-trigger review
- Comment `@architect-run` to manually re-trigger

---
