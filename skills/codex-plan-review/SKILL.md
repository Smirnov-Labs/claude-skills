---
name: codex-plan-review
description: Get a second opinion on your current implementation plan by sending it to Codex for independent review. Use after brainstorming, after writing a plan, or when you want to iterate on a plan before execution. Triggers on 'get a second opinion', 'review plan with codex', 'codex review', or 'iterate on plan'.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific delegated task, do NOT follow this skill — skip it and return to the task you were given.
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

### 2. Read and Summarize the Plan

Read the full plan file. Construct a prompt for Codex that includes:

- The complete plan content
- The project context (from CLAUDE.md or memory bank if relevant)
- A request for critical architectural review

### 3. Send to Codex

Codex reads the prompt on stdin. A long plan does not fit in a shell argument. Build the prompt with `cat`, so the plan is not retyped:

```bash
PLAN=<path to the plan>
d=$(mktemp -d)
{
  cat <<'EOF'
You are a senior architect reviewing an implementation plan. Your job is to find weaknesses, missing considerations, and improvements. Be direct and specific.

PROJECT CONTEXT:
<two or three lines on the project, from CLAUDE.md or the memory bank>

PLAN TO REVIEW:

EOF
  cat "$PLAN"
  cat <<'EOF'

Review this plan and provide:

1. **Structural Issues** — Are there missing steps, wrong ordering, or circular dependencies?
2. **Architectural Concerns** — Does the plan fight existing patterns? Are there simpler approaches?
3. **Risk Assessment** — What could go wrong? What assumptions are fragile?
4. **Missing Considerations** — What did the plan author overlook? (edge cases, error handling, testing, rollback)
5. **Specific Improvements** — Concrete suggestions, not vague advice. Reference specific plan sections.

Be critical. The goal is to strengthen the plan, not validate it.
EOF
} > "$d/prompt.md"

codex exec \
  -m gpt-6-astra \
  -c model_reasoning_effort="high" \
  --sandbox read-only \
  --skip-git-repo-check \
  -o "$d/review.md" \
  - < "$d/prompt.md" > "$d/codex.log" 2>&1
```

Run it in the background: a high-effort review of a long plan takes several minutes. The review is in `$d/review.md`. If the exit status is not 0, read the end of `$d/codex.log`. For a 400 "model is not supported", see Model below.

### 4. Present the Review

After Codex returns its review:

1. Present the Codex feedback to the user clearly
2. Highlight any blockers or high-severity concerns
3. Ask: "Want to incorporate any of this feedback into the plan?"

### 5. Iterate if Requested

If the user wants to update the plan:

1. Edit the plan file with the agreed changes
2. Optionally re-run Codex for another pass (ask first — avoid infinite loops)

## Model

`gpt-6-astra` is the pin: the frontier model on ChatGPT-account auth. Checked 2026-10-19 with codex-cli 0.163:

| Model | Use |
|---|---|
| `gpt-6-astra` | The pin. Frontier model, 272K context. |
| `gpt-6.1-sol` | Newest workhorse, 500K context. Use it if the plan does not fit in 272K. |
| `gpt-6-sol`, `gpt-5.6-sol`, `gpt-5.6-terra` | Older workhorse and balanced models. Don't pin them. |
| `gpt-6-luna`, `gpt-5.6-luna` | Fast and cheap. Too light for a review. |
| `gpt-5.5`, `gpt-5.4`, `gpt-5.4-codex`, `gpt-5.5-codex` | HTTP 400: "not supported when using Codex with a ChatGPT account". |

A 400 "model is not supported" means the pin is stale. Then:

1. Rerun once without `-m`. Codex then uses the model in `~/.codex/config.toml`.
2. Tell the user that the pin is stale.
3. List the current models, to choose a new pin:

   ```bash
   codex debug models | jq -r '.models[] | select(.visibility=="list") | .slug'
   ```

## Key Rules

- **Always use `gpt-6-astra`**. If Codex rejects it, see Model.
- **Always use `high` reasoning effort**
- **Always use `read-only` sandbox** — this is a review, not an edit
- **Never skip the plan lookup step** — if there's no plan, ask for one
- **Present Codex output faithfully** — don't filter or summarize away criticisms
- **Remind the user** they can ask Codex follow-up questions with `codex resume --include-non-interactive --last`. A plain `codex resume` hides `codex exec` sessions.
