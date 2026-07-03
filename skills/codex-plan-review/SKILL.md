---
name: codex-plan-review
description: Get a second opinion on your current implementation plan by sending it to Codex for independent review. Use after brainstorming, after writing a plan, or when you want to iterate on a plan before execution. Triggers on 'get a second opinion', 'review plan with codex', 'codex review', or 'iterate on plan'.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific delegated task, do NOT follow this skill — skip it and return to the task you were given.
</SUBAGENT-STOP>

# Codex Plan Review

Send the current working plan to Codex (gpt-5.5) for an independent second opinion. This skill is used to iterate on plans before committing to implementation.

## When to Use

- After brainstorming produces a design spec
- After writing an implementation plan
- When you want a critical review before executing a plan
- When the user says "get a second opinion" or "review this plan"

## Process

### 1. Find the Current Plan

Locate the most recent plan by checking these locations in order:

1. **Design specs**: `docs/superpowers/specs/*.md` (most recent by date prefix)
2. **Plan files**: `docs/superpowers/plans/*.md` (most recent by date prefix)
3. **Active context**: `.claude/memory-bank/activeContext.md` for references to current work

If no plan file is found, ask the user to point you to the plan or spec they want reviewed.

### 2. Read and Summarize the Plan

Read the full plan file. Construct a prompt for Codex that includes:

- The complete plan content
- The project context (from CLAUDE.md or memory bank if relevant)
- A request for critical architectural review

### 3. Send to Codex

Run Codex with these exact settings — **gpt-5.5 (strongest ChatGPT-account model), high effort, read-only**:

```bash
codex exec \
  -m gpt-5.5 \
  --config model_reasoning_effort="high" \
  --sandbox read-only \
  --skip-git-repo-check \
  --full-auto \
  2>/dev/null \
  "<prompt>"
```

**The prompt sent to Codex must follow this template:**

```
You are a senior architect reviewing an implementation plan. Your job is to find weaknesses, missing considerations, and improvements. Be direct and specific.

PROJECT CONTEXT:
<brief project description from CLAUDE.md or memory bank>

PLAN TO REVIEW:
<full plan content>

Review this plan and provide:

1. **Structural Issues** — Are there missing steps, wrong ordering, or circular dependencies?
2. **Architectural Concerns** — Does the plan fight existing patterns? Are there simpler approaches?
3. **Risk Assessment** — What could go wrong? What assumptions are fragile?
4. **Missing Considerations** — What did the plan author overlook? (edge cases, error handling, testing, rollback)
5. **Specific Improvements** — Concrete suggestions, not vague advice. Reference specific plan sections.

Be critical. The goal is to strengthen the plan, not validate it.
```

### 4. Present the Review

After Codex returns its review:

1. Present the Codex feedback to the user clearly
2. Highlight any blockers or high-severity concerns
3. Ask: "Want to incorporate any of this feedback into the plan?"

### 5. Iterate if Requested

If the user wants to update the plan:

1. Edit the plan file with the agreed changes
2. Optionally re-run Codex for another pass (ask first — avoid infinite loops)

## Key Rules

- **Always use `gpt-5.5`** — full `-codex` models (`gpt-5.4-codex`, `gpt-5.3-codex`, `gpt-5.5-codex`) and base `gpt-5.3` return HTTP 400 on ChatGPT-account auth; `gpt-5.5` is the strongest supported model
- **Always use `high` reasoning effort**
- **Always use `read-only` sandbox** — this is a review, not an edit
- **Never skip the plan lookup step** — if there's no plan, ask for one
- **Present Codex output faithfully** — don't filter or summarize away criticisms
- **Remind the user** they can run `codex resume` for follow-up questions
