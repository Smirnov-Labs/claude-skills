---
name: codex-review
description: Use when you want an independent Codex review of a plan, spec or code change at a major checkpoint or before merging, when asked for a "codex review" or "second opinion", or before writing `codex exec` by hand.
---

# Codex review

`codex-review` runs one read-only Codex review and prints a verdict. Hand-built `codex exec` lines kept failing in the same ways:

- stderr went to `/dev/null`, so a crash read as an empty review;
- the model pins went stale;
- agents ran `--help` to find the flags again;
- sleep loops waited for the output.

## Run it

Run it with `run_in_background: true`. A high-effort review takes several minutes, and you are told when it exits. Don't poll it and don't wrap it in a loop.

| To review | Command |
|---|---|
| An implementation plan | `codex-review plan docs/plans/feature.md` |
| A design spec | `codex-review spec docs/specs/feature.md` |
| This branch's commits | `codex-review diff` (`origin/<default branch>...HEAD`) |
| Other commits | `codex-review diff main..HEAD` (a single ref R means `R..HEAD`) |
| A PR | `codex-review diff --pr 123`, from a checkout of the PR branch |
| Your own prompt, as is | `codex-review prompt prompt.md` |

- `--context FILE` (repeatable) adds what the work must meet: the spec for a diff, the constraints for a plan.
- `--focus "..."` says what to check hardest.
- Commit before a diff review. Uncommitted changes are not in the diff.
- `codex-review --help` has the rest (`--out`, `--timeout`, `--model`, `--effort`, `--dry-run`).
- `codex-review` is on PATH where skillsync installed this skill. In a plugin install, call `<this skill's base directory>/bin/codex-review` by its full path, from the project directory.

## Read the result

It prints the prompt, review and log paths, then a verdict:

```
verdict FINDINGS · critical 0 · major 1 · minor 3 · 6m12s
  [MAJOR] The merge runs before the MERGED check
```

| Exit | Meaning |
|---|---|
| 0 | No Critical or Major findings (prompt mode: Codex answered) |
| 1 | Critical or Major findings, or a review it could not parse |
| 2 | No usable review: Codex failed, timed out, or said it could not review |
| 3 | Usage error |

Then:

1. Read `review.md`. The exit status is a summary, not the review.
2. Check each Critical and Major finding against the code or the plan. Codex can be wrong.
3. Fix the findings you confirmed. List the Minor ones in your report.
4. If you changed anything, commit and review the new HEAD.

On exit 2, read the log tail it prints. Don't report "Codex found nothing".

## Model

The pin is `gpt-6-astra`, checked on 2026-11-05 with codex-cli 0.166. `CODEX_REVIEW_MODEL` or `--model` overrides it.

| Model | Use |
|---|---|
| `gpt-6-astra` | The pin. Frontier model, 272K context. |
| `gpt-6.1-sol` | 500K context. Used on its own when the prompt passes 600,000 characters. |
| `gpt-6.1-terra`, `gpt-6-sol`, `gpt-5.6-*` | Older or balanced models. Don't pin them. |
| `gpt-6-luna`, `gpt-5.6-luna` | Fast and cheap. Too light for a review. |

If Codex rejects the pin as "not supported", the script runs once more with the model from `~/.codex/config.toml` and prints a note. Then update the pin: `codex debug models | jq -r '.models[] | select(.visibility=="list") | .slug'`.

## Common mistakes

| Mistake | What happens |
|---|---|
| `codex exec ... 2>/dev/null` | A crash leaves an empty review, and the work goes on as if Codex agreed. |
| A sleep loop that waits for `review.md` | Wasted turns. The background run tells you when it ends. |
| Exit 0 read as approval | Exit 0 means no Critical or Major findings were parsed. Read the review. |
| Reviewing uncommitted work | The review names no SHA, and the diff misses the edits. |
