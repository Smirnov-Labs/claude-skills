---
name: codex-plan-review
description: Get a second opinion on your current implementation plan by sending it to Codex for independent review. Use after brainstorming, after writing a plan, or when you want to iterate on a plan before execution. Triggers on 'get a second opinion', 'review plan with codex', 'codex review', or 'iterate on plan'.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific delegated task, do NOT follow this skill. Skip it and return to the task you were given.
</SUBAGENT-STOP>

# Codex Plan Review

Send the current working plan to Codex (`gpt-6-astra`) for an independent second opinion. This skill is used to iterate on plans before committing to implementation.

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

### 2. Pick the Context

Read the full plan, so you can weigh Codex's findings against it. Pick the file that holds the project's rules or constraints: `CLAUDE.md`, or the memory bank file that describes the work.

### 3. Send to Codex

Run the review with `codex-review`, from the codex-review skill, in the background:

```bash
codex-review plan "$PLAN" --context CLAUDE.md
```

`codex-review` is on PATH where skillsync installed the skills. In a plugin install, run it from this skill's base directory as `../codex-review/bin/codex-review`.

Add `--focus "..."` for what to check hardest. A high-effort review of a long plan takes several minutes, and you are told when it exits. It prints the review path and a verdict line. Exit 1 means Critical or Major findings. Exit 2 means there is no usable review: read the log tail it prints.

### 4. Present the Review

After Codex returns its review:

1. Present the Codex feedback to the user clearly
2. Highlight any blockers or high-severity concerns
3. Ask: "Want to incorporate any of this feedback into the plan?"

### 5. Iterate if Requested

If the user wants to update the plan:

1. Edit the plan file with the agreed changes
2. Optionally run Codex again for another pass. Ask first, so the review does not loop.

## Model

The model pin, its fallback and the dated model table live in the codex-review skill.
