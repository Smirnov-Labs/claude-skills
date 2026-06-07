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
[Document patterns as they emerge]

### User Preferences
[Document user's working style and preferences]

### Lessons Learned
[Document key insights from work sessions]

### Known Gotchas
[Document tricky areas or common pitfalls]

### Effective Approaches
[Document what works well for this project]

---

## Notes

- Memory Bank files are in `.claude/memory-bank/`
- Templates are provided - fill them out based on actual project
- Update frequently to maintain accuracy
- The Memory Bank is the primary context system for this project

## Skills Marketplace

This repo is a Claude Code skills marketplace hosted at `github:smirnov-labs/claude-skills`.

### Structure

- **`.claude-plugin/marketplace.json`** -- Registry that defines available plugins and their skills. Each plugin entry has a `name`, `description`, `source`, and a list of `skills` paths.
- **`skills/`** -- Directory containing individual skill definitions. Each skill is a subdirectory with:
  - `SKILL.md` -- Skill definition with YAML frontmatter (`name`, `description`) and the full skill prompt
  - Supporting reference files (frameworks, archetypes, analysis guides, etc.)

### Current Skills

| Skill | Plugin | Path | Purpose |
|-------|--------|------|---------|
| `presentation-blueprint` | `presentation-tools` | `skills/presentation-blueprint/` | Build pitch/technical/update decks end-to-end (analyze → strategize → outline → style → render) |
| `codex-plan-review` | `plan-utilities` | `skills/codex-plan-review/` | Send the current plan to Codex 5.4 (high effort, read-only) for an independent architectural review |
| `detect-overengineering` | `plan-utilities` | `skills/detect-overengineering/` | Audit a plan document for LLM-style overengineering — rubric pass + Codex adversarial pass + merged findings with proposed edits |
| `git-recon` | `git-recon` | `skills/git-recon/` | 12-month git-history health check — churn, bus factor, bug hotspots, velocity, firefighting |

### Current Commands

Commands live at `.claude/commands/<name>.md` and ship automatically with every plugin in this marketplace (since all plugins use `source: "./"`). Listed under a "plugin" column for discoverability.

| Command | Plugin | Path | Purpose |
|---------|--------|------|---------|
| `/pr` | `pr-utilities` | `.claude/commands/pr.md` | Commit changes, push, and create or update a PR |
| `/pr-fix` | `pr-utilities` | `.claude/commands/pr-fix.md` | Loop on a PR: read CI + SAR + inline reviews (including Codex), auto-commit fixes, repeat until clean |
| `/plan` | n/a (project-local) | `.claude/commands/plan.md` | Enter planning mode with Memory Bank review |
| `/loop-review` | n/a (project-local) | `.claude/commands/loop-review.md` | Iteratively refine the current plan through senior-architect review loops |
| `/memory` | n/a (project-local) | `.claude/commands/memory.md` | Update Memory Bank and compress old data if needed |

### marketplace.json Format

```json
{
  "name": "smirnovlabs-claude-skills",
  "plugins": [
    {
      "name": "presentation-tools",
      "description": "...",
      "source": "./",
      "skills": ["./skills/presentation-blueprint"]
    },
    {
      "name": "plan-utilities",
      "description": "...",
      "source": "./",
      "skills": ["./skills/codex-plan-review"]
    },
    {
      "name": "git-recon",
      "description": "...",
      "source": "./",
      "skills": ["./skills/git-recon"]
    }
  ]
}
```

### Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter
2. Add reference files alongside SKILL.md as needed
3. Add the skill path to the appropriate plugin in `marketplace.json` (or create a new plugin entry)

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

### Key Patterns Enforced
1. **Email Provider Consolidation**: All providers MUST use `EmailProcessingService`
2. **EventBus Contracts**: New events MUST update `EventBus.js` aggregateId derivation
3. **Multi-Tenant Isolation**: All queries MUST filter by `organizationId`
4. **API Routing**: Backend routes have NO `/api` prefix (Caddy handles it)
5. **Deployment Scripts**: Use `deploy-beta.sh` / `deploy-dev.sh`, not manual Docker
6. **Password Hashing**: NEVER manual hashing (User model has hook)
7. **Service Layer**: Follow `Routes → Services → Models` pattern
8. **Async Operations**: Long operations MUST use Redis queues
9. **Docker Rebuild**: Code changes require `--build` flag
10. **Import Pipeline**: Follow 3-phase pattern (Download → Selection → Processing)

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
