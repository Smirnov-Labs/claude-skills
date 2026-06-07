# Dogfood Notes — Initial Run

**Date:** 2026-05-06
**Target:** docs/superpowers/plans/2026-03-14-presentation-blueprint.md

## Findings count
- Cross-validated: 3
- Rubric-only: 0
- Codex-only: 6
- Total: 9

## Codex pass status
Succeeded. Model: gpt-5.5 (default, ChatGPT account — `gpt-4o` and `gpt-5.4-codex` are not available with this account type). Command executed with `--sandbox workspace-write` semantics (the SKILL.md prompt uses `--full-auto` which is deprecated but maps to the same behavior). 9 findings returned.

Note: The SKILL.md specifies `-m gpt-5.4-codex`. That model is unavailable on ChatGPT accounts; gpt-5.5 was used instead. The prompt and all other flags worked correctly. The SKILL.md should document the fallback or make the model configurable.

## Rubric calibration observations

**Patterns that fired (cross-validated):**

- **Pattern 9 (speculative extensibility):** Fired on "Pipeline Flowchart — Small dot digraph" in Task 1. Precision felt right — a DOT-rendered graph inside a lean skill hub is documentation ornamentation. Codex independently found the same signal. The anti-example in examples.md for Pattern 9 is about code extensibility (strategy patterns), not documentation style, so the suppression path is absent; the finding is correct.

- **Pattern 9 (speculative extensibility, second instance):** Fired on "style variations per presentation type" in Task 3. Felt right — the plan already delegates rendering decisions to the pptx skill and has a standalone style phase. Adding per-archetype style variations creates spec-level work that will be discarded anyway once the pptx skill handles it. Codex agreed.

- **Pattern 6 (useless DRY):** Fired on "Complete mapping for all three frameworks" in Task 3. The mapping largely restates content already in narrative-frameworks.md (Chunk 2). Codex independently identified this as bloat. Confidence is appropriate.

**Patterns that did not fire:**

Patterns 1, 2, 4, 5, 7, 8, 10, 11, 12, 13 — none applied. The plan is a markdown-authoring plan, so patterns about code structure (custom errors, file proliferation, backwards-compat shims, JSDoc, env vars, migration scripts, rollout phases) don't have meaningful hooks. The rubric's signal language is code-centric; plan-level equivalents for these patterns are mostly absent.

Pattern 3 (premature abstraction): the four-file structure could superficially match "create a service layer / adapter" but the anti-example in examples.md explicitly covers this: "Don't flag: Storage interface with S3Storage and LocalStorage — two real implementations exist." Analogously, the four reference files are each load-bearing with distinct content (narrative frameworks, archetypes, source analysis patterns). Correct suppression.

Pattern 8 (over-tested impossible paths): Task 5-7 form a test suite, but the test cases themselves test real LLM behavior (will the model fabricate metrics? skip approval gates?). Not type-system-guaranteed outcomes. Correct suppression.

**False positives caught by examples.md:**

- Pattern 3 would have fired on the four-file architecture without examples.md. The "two real implementations" anti-example was the suppression trigger: all four files serve distinct, non-overlapping content domains.
- Pattern 10 (file proliferation) might have fired naively — four files for a skill — but the anti-example requires "<100 lines total." Each reference file is specified to be ~100-200 lines individually. Correct suppression.

## Suggested rubric updates (for follow-up)

- Pattern 9: The current signal and examples focus on code-level extensibility (strategy patterns, pluggable providers). Add a documentation-level signal variant: "Include a DOT/Mermaid diagram / design matrix / mapping table that restates content already defined elsewhere." The flowchart and archetype-framework mapping both match this, but the rubric signal didn't directly point there — Codex carried the finding.

- General: The rubric patterns 1, 2, 4, 5, 7, 8, 10, 11, 12, 13 are almost entirely code-centric. For plans that produce only markdown/documentation artifacts (skills, reference files, specs), most of the rubric has no surface area. Consider adding a "Plan-level process bloat" category covering: unnecessary experiment phases (pre/post baseline tests), mandatory parallelism directives, redundant validation sections. Codex found all 6 of these; the rubric found none.

## New patterns observed (not in current rubric)

- **Process theatre for low-stakes work.** The plan mandates a subagent-driven-development workflow and parallelism for creating four short markdown files. Neither adds value; both add coordination overhead. Signal: "REQUIRED: Use superpowers:subagent-driven-development" / "Tasks N-M are independent and can run in parallel" when the total work is a small set of authored files. Edit: remove the agentic directive; sequence the file creation manually.

- **Redundant guardrail duplication.** "Guardrails" section + "Red Flags" table covering the same constraints in two slightly different formats. Signal: a plan that defines a "never do" list and a separate "guardrails" section where the entries are paraphrases of each other. Edit: merge into one section.

- **Anecdotal-loophole patching.** Task 7 (Refactor phase) instructs the implementer to patch the skill based on rationalizations observed in Task 5 (baseline test). This is speculative — it assumes baseline failures will be observed, and that patching for one agent's rationalizations improves the skill for all. Signal: "update X with explicit counters for rationalizations observed during Y." Edit: collapse into the validation step: "if validation fails, update the relevant instruction and rerun."

## Skill-prompt issues

- **Model name mismatch.** SKILL.md specifies `-m gpt-5.4-codex` in the Codex command. This model is unavailable on ChatGPT-linked Codex accounts; the invocation fails silently (exit 1) when specified explicitly. The default model (gpt-5.5 at time of this run) worked. Suggest: document the model as a suggested value and add a fallback note, or omit `-m` and rely on the default.

- **`--full-auto` deprecation.** SKILL.md uses `--full-auto`; Codex 0.128.0 emits a deprecation warning and maps it to `--sandbox workspace-write`. This is harmless but noisy when stderr is not redirected. The command already has `2>/dev/null`, so the warning is suppressed in practice. No action needed but worth noting for when the flag is eventually removed.

- **Prompt injection via stdin vs. positional arg.** SKILL.md passes the Codex prompt as a positional argument (last arg in the command). For long prompts with embedded plan content this exceeds shell argument length limits on some systems. In practice, piping via stdin (`echo "$PROMPT" | codex exec ...`) worked correctly. The SKILL.md instruction is technically correct per Codex's --help, but a note about the stdin alternative would make the skill more robust.

- **Pass A instruction granularity.** SKILL.md says "For each H2 section in the plan, walk every rubric pattern." This worked, but the rubric patterns are grouped under H2 headers with H3 sub-entries. "Every rubric pattern" means all 13 H3 entries, not the 5 H2 groups. The instruction is slightly ambiguous — could be read as 5 checks (H2 groups) rather than 13 (H3 patterns). Suggest: "Walk all 13 rubric patterns (H3 entries) for each H2 section in the plan."
