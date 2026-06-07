# Smirnov Labs Claude Skills

A Claude Code **skills marketplace** and **starter template** that bundles reusable AI workflows, a Memory Bank system for persistent project context, custom slash commands, and an automated architecture reviewer -- everything you need to supercharge Claude Code on any project.

## Quick Start: Install Skills

```bash
# 1. Register this marketplace (one-time)
/plugin marketplace add smirnov-labs/claude-skills

# 2. Install any plugin (pick the ones you want)
/plugin install presentation-tools@smirnovlabs-claude-skills
/plugin install plan-utilities@smirnovlabs-claude-skills
/plugin install git-recon@smirnovlabs-claude-skills
/plugin install pr-utilities@smirnovlabs-claude-skills
```

Or from the CLI outside a session:

```bash
claude plugin marketplace add smirnov-labs/claude-skills
claude plugin install presentation-tools@smirnovlabs-claude-skills
```

Once installed, skills activate automatically based on what you ask. Say "build a pitch deck for this project", "get a second opinion on this plan", or "run a git recon on this repo" — or invoke directly with `/presentation-blueprint`, `/codex-plan-review`, or `/git-recon`.

### Available Skills

| Skill | Plugin | What it does | Trigger phrases |
|-------|--------|--------------|-----------------|
| **presentation-blueprint** | `presentation-tools` | End-to-end presentation consultant: analyzes codebases/websites/projects, crafts strategic blueprints, and renders polished decks via `document-skills:pptx` | "build a deck", "create a presentation", "pitch deck for" |
| **codex-plan-review** | `plan-utilities` | Sends your current plan to Codex 5.4 (high-effort, read-only) for an independent architectural second opinion before you execute | "review plan with codex", "get a second opinion", "iterate on plan" |
| **detect-overengineering** | `plan-utilities` | Audits an implementation-plan doc for LLM-style overengineering: a rubric-driven Claude pass plus a Codex adversarial pass, merged into specific edits that slim the plan | "check this plan for bloat", "is this overengineered", "detect overengineering" |
| **git-recon** | `git-recon` | 12-month git-history health check: surfaces high-churn files, bus factor, bug hotspots, velocity trends, and firefighting patterns before you read any code | "git recon", "codebase health check", "where are the landmines" |
| **reading-bot-pr-reviews** | `pr-utilities` | Read-only: fetches every automated PR review (Codex across its 3 endpoints + the Architecture/SAR review), filters on exact bot logins, and reports a severity-classified merge verdict so no finding — or clean pass — is missed | "what did the bots say", "read the PR reviews", "did Codex/the SAR pass" |

### Prerequisites

The `presentation-blueprint` skill requires `document-skills:pptx` for rendering:

```bash
/plugin install document-skills@anthropic-agent-skills
```

The `codex-plan-review` skill requires the [Codex CLI](https://github.com/openai/codex) on your `PATH` with a `gpt-5.4-codex` model available.

The `git-recon` skill needs only `git` — runs locally against the repo you're standing in.

The `reading-bot-pr-reviews` skill requires the [GitHub CLI](https://cli.github.com/) (`gh`) authenticated against the repo, and a repo whose PRs are reviewed by Codex and/or an Architecture-Review GitHub Action.

## What's in This Repo

| Component | Location | Description |
|-----------|----------|-------------|
| **Skills Marketplace** | `.claude-plugin/marketplace.json` + `skills/` | Installable skills that other Claude Code instances can pull from `github:smirnov-labs/claude-skills` |
| **Memory Bank** | `.claude/memory-bank/` | Structured documentation templates that give Claude full project context across sessions |
| **Custom Slash Commands** | `.claude/commands/` | `/plan`, `/pr`, `/memory`, `/loop-review` -- ready-to-use workflows |
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
└── reading-bot-pr-reviews/      # Automated PR-review reader skill
    └── SKILL.md                 # Skill definition
```

### Key Components

1. **Skills Marketplace** (`.claude-plugin/` + `skills/`)
   - Installable via `github:smirnov-labs/claude-skills`
   - Ships with four plugins: `presentation-tools`, `plan-utilities`, `git-recon`, and `pr-utilities`

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
2. Add a `SKILL.md` with YAML frontmatter (`name` and `description`)
3. Add any supporting reference files (e.g., frameworks, archetypes, analysis guides)
4. Register the skill path in `.claude-plugin/marketplace.json`
5. Push to GitHub

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
