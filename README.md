# Smirnov Labs Claude Skills

Public Claude Code skills, plus `skillsync`, a small script that installs them on every machine you use and keeps them current. The repo is also a **starter template**: a Memory Bank system for persistent project context, custom slash commands, and an automated architecture reviewer.

## Quick Start: Install Skills

```bash
git clone -q https://github.com/Smirnov-Labs/claude-skills ~/.local/share/skillsync/claude-skills \
  && ~/.local/share/skillsync/claude-skills/bin/skillsync
```

That clones the repo and symlinks each skill into `~/.claude/skills/`, plus the commands the skills ship (`prbots`, and `skillsync` itself) into `~/.local/bin/`. New Claude Code sessions pick the skills up.

| Command | What it does |
|---------|--------------|
| `skillsync` | Pull every skills repo, then relink. Add `-q` for cron, e.g. `17 * * * * ~/.local/bin/skillsync -q` |
| `skillsync add <git-url>` | Add another skills repo, such as a private one. It only installs where the clone succeeds |
| `skillsync link` | Relink without touching the network |
| `skillsync list` | Show the repos it manages |

skillsync never overwrites a skill directory or command you made by hand, never links a command that would shadow one already on your PATH, and only removes links that point into its own clones. To keep a skill off one machine, put its name in `~/.config/skillsync/exclude`.

### Or as Claude Code plugins

Some of the skills are also published as plugins (their names get a `plugin:` prefix):

```bash
/plugin marketplace add smirnov-labs/claude-skills
/plugin install pr-utilities@smirnovlabs-claude-skills
```

Use one method or the other on a machine, not both, or each skill loads twice.

### Available Skills

| Skill | What it does | Trigger phrases |
|-------|--------------|-----------------|
| **presentation-blueprint** | End-to-end presentation consultant: analyzes codebases/websites/projects, crafts strategic blueprints, and renders polished decks via `document-skills:pptx` | "build a deck", "create a presentation", "pitch deck for" |
| **codex-plan-review** | Sends your current plan to Codex 5.4 (high-effort, read-only) for an independent architectural second opinion before you execute | "review plan with codex", "get a second opinion", "iterate on plan" |
| **detect-overengineering** | Audits an implementation-plan doc for LLM-style overengineering: a rubric-driven Claude pass plus a Codex adversarial pass, merged into specific edits that slim the plan | "check this plan for bloat", "is this overengineered", "detect overengineering" |
| **git-recon** | 12-month git-history health check: surfaces high-churn files, bus factor, bug hotspots, velocity trends, and firefighting patterns before you read any code | "git recon", "codebase health check", "where are the landmines" |
| **watching-pr-bot-reviews** | Waits for and reads the automated PR reviewers (Codex, the Architecture/SAR review, CI) with `prbots`: one background `prbots wait`, then a digest with a CLEAN / FIX / BLOCK / PENDING verdict for the PR's HEAD commit | "what did the bots say", "wait for Codex", before merging |
| **pr-fix** | `/pr-fix`: drives a PR to clean by fixing CI failures and review feedback, pushing, and waiting with `prbots`, round after round (runs only when you invoke it) | `/pr-fix` |
| **bd-to-br-migration** | Migrates docs and scripts from bd (beads) to br (beads_rust) | "migrate from bd to br", "beads migration" |
| **debugging-kubernetes-rollouts** | Systematic debugging of failed rollouts, ArgoCD sync issues, pod failures, and image pulls | "rollout is stuck", "ArgoCD won't sync" |
| **debugging-nodejs-apps** | Systematic debugging of Node.js startup, dependency, and runtime failures | "service won't start", "npm error" |
| **operating-frappe-on-kubernetes** | Keeps a Frappe / ERPNext instance on Kubernetes healthy: why runtime config only sticks via `bench set-config -g`, first-site bootstrap, v15→v16 upgrades, Error Log / email / PDF debugging | "bench migrate", "set-config won't take", "Error Log" |
| **hyprland-lua** | Scripting, controlling, and debugging a Hyprland compositor configured in Lua | "hyprctl", "special workspace won't toggle" |
| **quickshell-bar** | Editing and debugging a Quickshell (Qt6/QML) status bar on Hyprland | "add a bar module", "bar renders blank" |
| **de-slopping** | Tightens a written deliverable (PR or commit message, design doc, README, runbook, report, release note): cuts hedges and filler, and checks Simplified Technical English rules with the bundled `ste_lint.py`. Includes an optional `slop_guard` Stop hook | "de-slop this", "tighten this", before finalizing a write-up |
| **minto-pyramid** | Restructures a write-up answer-first with the Minto Pyramid: the conclusion, then grouped supporting points | "restructure this", "de-waffle", "lead with the answer" |
| **humanizer** | Removes signs of AI-generated writing (vendored from [blader/humanizer](https://github.com/blader/humanizer)) | "humanize this text" |
| **nonstop** | Autonomous work mode driven by a Stop hook (vendored from [andylizf/nonstop](https://github.com/andylizf/nonstop); its `UPSTREAM` file has the hook line) | "/nonstop", "keep working while I'm away" |

### Prerequisites

The `presentation-blueprint` skill requires `document-skills:pptx` for rendering:

```bash
/plugin install document-skills@anthropic-agent-skills
```

The `codex-plan-review` skill requires the [Codex CLI](https://github.com/openai/codex) on your `PATH` with a `gpt-5.4-codex` model available.

The `git-recon` skill needs only `git` — runs locally against the repo you're standing in.

The `watching-pr-bot-reviews` and `pr-fix` skills require the [GitHub CLI](https://cli.github.com/) (`gh`) authenticated against the repo, and a repo whose PRs are reviewed by Codex and/or an Architecture-Review GitHub Action.

## What's in This Repo

| Component | Location | Description |
|-----------|----------|-------------|
| **Skills** | `skills/` + `bin/skillsync` | Skills installed with skillsync, or as plugins through `.claude-plugin/marketplace.json` |
| **Memory Bank** | `.claude/memory-bank/` | Structured documentation templates that give Claude full project context across sessions |
| **Custom Slash Commands** | `.claude/commands/` | `/plan`, `/pr`, `/memory`, `/loop-review` -- workflows for working inside this repo |
| **Architect-Gate** | `.github/claude/` | Automated architecture review that runs on every PR via CI |

## Table of Contents

- [Quick Start: Install Skills](#quick-start-install-skills)
- [Using as a Project Template](#using-as-a-project-template)
- [What's Included](#whats-included)
- [How It Works](#how-it-works)
- [Usage Guide](#usage-guide)
- [Memory Bank Files](#memory-bank-files)
- [Best Practices](#best-practices)
- [Advanced Usage](#advanced-usage)
- [Adding Your Own Skills](#adding-your-own-skills)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Using as a Project Template

Want the full Memory Bank + Architect-Gate + commands for a new project? Clone the repo:

```bash
git clone https://github.com/smirnov-labs/claude-skills.git my-project
cd my-project
rm -rf .git  # Remove template git history
git init     # Start fresh
```

Then fill out `.claude/memory-bank/projectbrief.md` with your project details -- this is your foundation. Work through the other template files (`productContext.md`, `systemPatterns.md`, `techContext.md`, `activeContext.md`, `progress.md`) as your project takes shape.

### Why a Memory Bank?

Claude Code's memory resets between sessions. The Memory Bank solves this:

- **Structured Documentation**: Pre-built templates for capturing project context
- **Automatic Context Loading**: Claude reads your memory bank at every session start
- **Planning Workflows**: Built-in `/plan` command for structured feature development
- **Project Intelligence**: System that learns and captures project-specific patterns

## What's Included

```
.claude/
├── claude.md                    # Main configuration & project intelligence
├── commands/
│   ├── plan.md                  # /plan — structured feature planning
│   ├── pr.md                    # /pr — pull request workflow
│   ├── memory.md                # /memory — memory bank management
│   └── loop-review.md           # /loop-review — iterative plan refinement
└── memory-bank/
    ├── QUICKSTART.md            # Quick start guide
    ├── memory-rules.md          # Complete system documentation
    ├── projectbrief.md          # Foundation document (template)
    ├── productContext.md        # Product vision (template)
    ├── systemPatterns.md        # Architecture patterns (template)
    ├── techContext.md           # Tech stack & setup (template)
    ├── activeContext.md         # Current work focus (template)
    └── progress.md              # Status tracking (template)

.claude-plugin/
└── marketplace.json             # Skills marketplace registry

.github/claude/
├── architect-gate.yml           # CI workflow for architecture review
└── ...                          # Review prompts and configuration

skills/
├── presentation-blueprint/      # Presentation consultant skill
│   ├── SKILL.md                 # Skill definition
│   ├── narrative-frameworks.md  # Reference: storytelling structures
│   ├── slide-archetypes.md      # Reference: slide design patterns
│   └── source-analysis.md       # Reference: source evaluation guide
├── codex-plan-review/           # Codex second-opinion skill
│   └── SKILL.md                 # Skill definition
├── detect-overengineering/      # Plan overengineering audit skill
│   └── SKILL.md                 # Skill definition
├── git-recon/                   # Git history health-check skill
│   └── SKILL.md                 # Skill definition
├── watching-pr-bot-reviews/     # PR-bot waiter and reader skill
│   ├── SKILL.md                 # Skill definition
│   └── bin/prbots               # The prbots command (skillsync puts it on PATH)
├── pr-fix/                      # /pr-fix loop
│   └── SKILL.md                 # Skill definition
└── ...                          # More skills; see the table above

bin/
└── skillsync                    # Installs and updates skills on a machine
```

### Key Components

1. **Skills** (`skills/` + `bin/skillsync`)
   - Installed with `skillsync` (see Quick Start), or as plugins via `.claude-plugin/marketplace.json`
   - The plugin marketplace ships four plugins: `presentation-tools`, `plan-utilities`, `git-recon`, and `pr-utilities`

2. **Slash Commands** (`.claude/commands/`)
   - `/plan` -- structured feature planning with clarifying questions
   - `/pr` -- pull request creation workflow
   - `/memory` -- memory bank review and update
   - `/loop-review` -- iterative plan refinement loop

3. **Memory Bank** (`.claude/memory-bank/`)
   - 6 core template files for project documentation
   - Complete system documentation
   - Quick start guide

4. **Architect-Gate** (`.github/claude/`)
   - Automated architecture review on every PR
   - Anti-pattern detection and severity scoring
   - Posts a System Architecture Review (SAR) comment

5. **Configuration** (`.claude/claude.md`)
   - Automatic memory loading via `alwaysApply: true`
   - Project intelligence journal
   - Instructions for Claude on how to use the system

## How It Works

### Automatic Context Loading

The `.claude/claude.md` file has `alwaysApply: true` configured, which means:

1. **Every Session Start**: Claude automatically reads the instructions in `claude.md`
2. **Memory Bank Loading**: Instructions tell Claude to read all memory bank files in order
3. **Immediate Context**: Claude has full project understanding without you explaining anything

### File Hierarchy

Files build upon each other logically:

```
projectbrief.md (Foundation)
    ├── productContext.md (Why it exists)
    ├── systemPatterns.md (How it's built)
    └── techContext.md (What technologies)
        └── activeContext.md (Current state - synthesizes all)
            └── progress.md (Tracks active context over time)
```

### Update Workflow

When you've made significant changes:

```
update memory bank
```

Claude will:
1. Review **ALL** memory bank files (mandatory)
2. Update files that need changes
3. Focus on `activeContext.md` and `progress.md`
4. Document new patterns in `claude.md`

## Usage Guide

### Starting a New Session

Just open Claude Code - memory loads automatically:

```bash
claude
```

Claude now has full context. Start working immediately:

```
Let's continue with the authentication feature
```

### Planning a Feature

Use structured planning for complex work:

```
/plan

I want to add user authentication with OAuth
```

Claude will:
- Review memory bank
- Ask clarifying questions (OAuth provider? Token storage? Session management?)
- Draft comprehensive plan
- Get your approval
- Execute systematically

### Daily Workflow

1. **Start Session**: Open Claude Code (context loads automatically)
2. **Check Context**: Claude references `activeContext.md` for current priorities
3. **Work**: Implement features, fix bugs, refactor
4. **Update**: Say "update memory bank" after significant changes
5. **Plan Next**: Use `/plan` for next major feature

### Documenting as You Go

Update relevant files during development:

- **Making architectural decisions?** → Update `systemPatterns.md`
- **Adding dependencies?** → Update `techContext.md`
- **Completing features?** → Update `progress.md`
- **Switching focus?** → Update `activeContext.md`

Say "update memory bank" and Claude will help you document.

## Memory Bank Files

### projectbrief.md
**Purpose**: Foundation document
**Update Frequency**: Rarely (only when project scope changes)
**Contains**: Goals, scope, constraints, success criteria

This is your source of truth. All other files derive from it.

### productContext.md
**Purpose**: Product vision and user experience
**Update Frequency**: Occasionally (when product direction shifts)
**Contains**: Problems solved, user workflows, requirements

Answers "why does this exist?" and "who is it for?"

### systemPatterns.md
**Purpose**: Architecture and technical patterns
**Update Frequency**: Regularly (as patterns emerge)
**Contains**: Architecture, design patterns, technical decisions, critical paths

Include code examples and file references with line numbers.

### techContext.md
**Purpose**: Technology stack and setup
**Update Frequency**: When adding/removing dependencies
**Contains**: Tech stack, dependencies, setup instructions, infrastructure

Your technical reference manual.

### activeContext.md
**Purpose**: Current work focus
**Update Frequency**: Very frequently (after every significant change)
**Contains**: Current focus, recent changes, next steps, decisions in progress

Your most dynamic file - reflects immediate state.

### progress.md
**Purpose**: Status tracking
**Update Frequency**: Frequently (as features complete)
**Contains**: Completed work, in-progress items, planned features, known issues

Shows project health and what's left to build.

## Best Practices

### 1. Start with the Brief

Fill out `projectbrief.md` thoroughly before other files. It's your foundation.

### 2. Keep activeContext.md Current

This is your most important file for day-to-day work. Update it frequently:
- After implementing features
- When changing focus
- When making important decisions
- When encountering challenges

### 3. Be Specific

Vague documentation is worse than no documentation:

**Bad**: "Fixed the bug in the auth system"
**Good**: "Fixed OAuth token refresh race condition in `src/auth/token-manager.ts:156` by adding mutex lock"

### 4. Include File References

Always include file paths with line numbers:

```markdown
Authentication is handled in `src/auth/oauth.ts:45-120`
```

This helps Claude (and humans) find the code quickly.

### 5. Document the Why

Don't just document what you did - document why:

**Bad**: "Using PostgreSQL"
**Good**: "Using PostgreSQL because we need ACID transactions for financial data and team has expertise"

### 6. Update Regularly

Don't let memory bank get stale. Update after:
- Completing features
- Making architectural decisions
- Discovering new patterns
- Changing dependencies
- Shifting focus

## Advanced Usage

### Adding Custom Context Files

Create additional files in `.claude/memory-bank/` for complex areas:

```
.claude/memory-bank/
├── [core files...]
├── features/
│   ├── authentication.md
│   └── payment-processing.md
├── integrations/
│   ├── stripe-api.md
│   └── sendgrid-api.md
└── testing/
    └── e2e-strategy.md
```

Reference them in `claude.md` for automatic loading.

### Custom Slash Commands

Add more commands in `.claude/commands/`:

```bash
# Create a review command
cat > .claude/commands/review.md << 'EOF'
---
description: Review and improve code quality
---

Review the codebase for:
1. Code quality issues
2. Security vulnerabilities
3. Performance optimizations
4. Documentation gaps

Provide specific recommendations with file references.
EOF
```

Use with: `/review`

### Project Intelligence Growth

The `.claude/claude.md` file grows smarter over time. Add sections like:

```markdown
## Project-Specific Patterns

### Error Handling
- Always use custom AppError class
- Include error codes and user messages
- Log with structured logging

### API Design
- RESTful conventions
- Consistent response format: {data, error, meta}
- Version all endpoints: /api/v1/...
```

Claude will learn and apply these patterns automatically.

### Team Usage

For team projects:

1. **Onboarding**: New members read memory bank to understand project
2. **Knowledge Sharing**: Memory bank is living documentation
3. **Decision History**: `systemPatterns.md` explains why things are built certain ways
4. **Consistency**: Everyone works from same understanding

## Adding Your Own Skills

1. Create a new directory under `skills/` (e.g., `skills/my-new-skill/`)
2. Add a `SKILL.md` with YAML frontmatter (`name` matching the directory, and a `description` starting with "Use when")
3. Add any supporting reference files, and put executables the skill calls in its `bin/` (skillsync puts them on PATH)
4. Run `skillsync link` to try it, then open a PR
5. Optionally list it under a plugin in `.claude-plugin/marketplace.json` for `/plugin` users

## Troubleshooting

### Claude Doesn't Have Context

**Problem**: Claude asks about basic project info despite memory bank

**Solutions**:
1. Verify `.claude/claude.md` has `alwaysApply: true`
2. Check that memory bank files are filled out (not just templates)
3. Try explicitly saying "Read the memory bank first"
4. Restart Claude Code session

### Memory Bank Out of Date

**Problem**: Documentation doesn't match current code

**Solution**:
```
update memory bank
```

Then work with Claude to update each file systematically.

### Too Much Information

**Problem**: Memory bank files are overwhelming

**Solution**:
- Focus on `activeContext.md` and `progress.md` for daily work
- Keep `projectbrief.md` concise (1-2 pages max)
- Use additional context files for detailed specs
- Remember: better to have some context than none

### Planning Workflow Not Working

**Problem**: `/plan` command doesn't trigger properly

**Solutions**:
1. Verify `.claude/commands/plan.md` exists
2. Check file has proper YAML frontmatter with `description`
3. Try restarting Claude Code
4. Use alternative: just say "Let's plan this feature carefully"

## FAQ

### Do I need to fill out all memory bank files?

Start with `projectbrief.md` and `activeContext.md`. Add others as your project grows. Some context is better than none.

### How often should I update the memory bank?

- `activeContext.md`: After every significant change
- `progress.md`: When features complete or status changes
- Others: When architectural decisions are made or patterns emerge

### Can I use this with existing projects?

Absolutely! Just:
1. Copy `.claude/` directory to your project
2. Fill out memory bank files based on current state
3. Start using Claude Code with full context

### What if my project changes significantly?

Update `projectbrief.md` first (it's the foundation), then cascade changes to other files. Say "update memory bank" and work with Claude to revise documentation.

### Is this only for Claude Code?

While designed for Claude Code, the memory bank structure works great for:
- Human team members (excellent documentation)
- Other AI tools
- Project handoffs
- Future reference

## Contributing

Found a way to improve this repo? Contributions welcome!

1. Fork the repository
2. Create a feature branch
3. Make your improvements
4. Submit a pull request

Ideas for contributions:
- New skills
- Additional memory bank templates
- More slash commands
- Documentation improvements

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Smirnov Labs

Built and maintained by [Smirnov Labs](https://smirnovlabs.com/). We help teams build smarter with AI-powered workflows and developer tooling.

If this repo saved you time or sparked ideas, we'd love to hear from you -- reach out at [smirnovlabs.com](https://smirnovlabs.com/) or open an issue to say hello.
