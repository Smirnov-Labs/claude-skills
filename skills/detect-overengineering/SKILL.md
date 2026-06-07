---
name: detect-overengineering
description: Use when reviewing an implementation plan document (docs/superpowers/plans/*.md or similar) for LLM-style overengineering before implementation. Runs a rubric-driven Claude pass plus a Codex adversarial pass, merges findings, and proposes specific edits to slim the plan. Triggers on 'check this plan for bloat', 'is this overengineered', 'detect overengineering', or invoked as /detect-overengineering.
---

# detect-overengineering

Audit an implementation plan document for LLM-style overengineering. Two passes (rubric-driven Claude pass + Codex adversarial pass) merge into a single report of specific edits to slim the plan before code is written.

Sits between `writing-plans` and `executing-plans` in the superpowers workflow. Cheaper to fix bloat in a plan than in merged code.

## Prerequisites

Verify `codex` is on PATH:

```bash
codex --version
```

If missing, instruct user to install Codex CLI (`npm install -g @openai/codex`) and stop.

## Process

### 1. Discover the plan

Look for plan files in this priority order; pick the most recently modified:

1. `docs/superpowers/plans/*.md`
2. `docs/superpowers/specs/*.md`
3. `docs/plans/*.md`

If zero matches, ask the user for the path.
If multiple matches in the top-priority directory have mtimes within 24h of each other, present a numbered list and ask which to review.

### 2. Pass A — Rubric pass (Claude in-session)

Read `./rubric.md` and `./examples.md`.

For each H2 section in the plan, walk every rubric pattern:
- Look for the pattern's plan-level signal in the section text
- If matched, check `examples.md` for "don't flag" look-alikes — suppress if the matched text fits a don't-flag case better than a flag case
- Otherwise emit a finding

Each finding is a structured record:

```
{
  source: "rubric",
  pattern_id: 3,
  plan_section: "## 4. Service layer",
  evidence: "Define IUserRepository...",
  rationale: "One consumer, one implementation. The interface is a name without substance.",
  suggested_edit: "Strike the interface (lines 47-58). Replace IUserRepository references with UserRepository directly.",
  confidence: "high"
}
```

### 3. Pass B — Codex adversarial pass

Run Codex with this exact command (matches `codex-plan-review` for consistency — non-spark model, high effort, read-only):

```bash
codex exec \
  -m gpt-5.4-codex \
  --config model_reasoning_effort="high" \
  --sandbox read-only \
  --skip-git-repo-check \
  --full-auto \
  2>/dev/null \
  "<prompt>"
```

The prompt sent to Codex must follow this template:

```
You are auditing an implementation plan for LLM-style overengineering —
features that LLM-authored plans tend to over-include but that don't
serve the actual goal. Use this rubric as a lens but feel free to flag
patterns it misses:

<RUBRIC CONTENT FROM rubric.md>

PLAN:

<FULL PLAN CONTENT>

For each issue, return:
- Plan section (exact heading from the plan)
- Quoted evidence (a phrase from the plan, verbatim)
- Why it's overengineering for THIS plan's stated goals
- Specific suggested edit (which lines to cut, collapse, or rewrite)

Skip generic architectural advice. Focus only on bloat the author should
cut before writing code. Be direct and opinionated.
```

Parse Codex's prose response into the same finding shape with `source: "codex"`.

### 4. Merge findings

For each rubric finding F, scan codex findings for matches:
- Same `plan_section` AND ≥50% phrase overlap in `evidence` → merge into one finding tagged `source: "both"`, confidence `high`
- Same `plan_section`, different evidence → keep separate, retain individual sources
- Different sections → keep separate

Sort the final list:
1. `source: "both"` first, in plan order
2. `source: "rubric"`, sorted by confidence desc, then plan order
3. `source: "codex"`, sorted by plan order

### 5. Present the report

Render this markdown directly in the conversation:

```
# Overengineering review: <plan path>

<N> findings (<X> cross-validated, <Y> rubric-only, <Z> codex-only)

──────────────────────────────────────────────────────────────────────
## Finding 1 — <pattern name>  [<SOURCE> · <confidence>]

Section: <H2 heading from plan>
Evidence: "<quote>"
Why bloat: <rationale>

Proposed edit:
  <specific change>

──────────────────────────────────────────────────────────────────────
## Finding 2 — ...
```

If zero findings:

```
# Overengineering review: <plan path>

Plan looks clean against the current rubric. Codex's adversarial pass
also found nothing actionable.
```

### 6. Apply approved edits

After the report, prompt:

> "I have N proposed edits. Apply all, walk through one-by-one, or cherry-pick by number?"

Modes:

| Mode | Behavior |
|---|---|
| **all** | Apply every edit in plan order via `Edit` tool. Show diff summary. |
| **walk** | For each finding: re-display, ask `apply / skip / modify`. `modify` lets the user dictate a different edit before applying. |
| **cherry-pick** | User passes `apply 1,3,5-7,12`. Apply those, skip the rest. |

**Edit safety:** every `Edit` call uses an exact-match `old_string` derived from the finding's evidence quote and a precise `new_string` derived from the suggested edit. No regex, no replace_all. If `old_string` doesn't match (user edited the plan between report and apply), stop and re-prompt that finding. Never silently proceed.

After all edits land, summarize:

```
Applied <X> of <N> edits. Plan reduced: <before> → <after> lines (<delta>%).
Skipped: <list of finding numbers>.
Re-run /detect-overengineering to verify? (y/N)
```

## Edge cases

- **Zero findings:** report says so, no edit prompt.
- **Plan has uncommitted changes:** warn the user but proceed; they own the diff.
- **Plan file >2000 lines:** chunk the rubric pass by H2 section. Codex still gets the full plan (handles long context natively).
- **Codex unavailable / fails:** continue with rubric pass only. Report header notes "adversarial pass unavailable."
- **No plan auto-discovered:** prompt the user for a path. Do not pick a default.

## Key rules

- **Always read rubric.md AND examples.md** before the rubric pass — examples suppress false positives.
- **Always use exact-match edits** — never regex or replace_all.
- **Never apply edits without explicit user approval** — even in "all" mode, the user is approving the batch.
- **Present Codex output faithfully** — don't filter criticisms; merge what overlaps with rubric findings, keep the rest.
- **One plan per invocation.**
