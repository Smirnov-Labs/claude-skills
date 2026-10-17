---
name: de-slopping
description: Use before you finalize a written deliverable (a PR or commit message, design doc, README, runbook, report, or release note), or when asked to de-slop, tighten, plain-English, or cut hedges and filler from text. Also before you claim a writing deliverable is done.
argument-hint: <text or file path; or "audit" to report findings only>
---

# de-slopping

A finishing pass that strips AI-slop from writing before the reader sees it.
Inspired by ASD-STE100 Simplified Technical English, the aerospace standard
for flight manuals, where one misread sentence can kill someone.

AI prose fails the opposite way. Sentences run long. Claims hedge. Big words
do small jobs. Filler sounds like content. This pass removes that. A linter
catches the countable slop. I apply the rest by judgment.

## When to run it

First classify the text. The mode decides how hard you cut.

- **Strict** (every rule): PR and commit messages, design docs, READMEs,
  runbooks, reports, release notes. Any artifact a reader acts on.
- **Light** (cut slop, hedges, em-dashes, and the swap words; keep voice,
  rhythm, and normal sentence length): chat replies, explanations, teaching.
- **Exempt** (do not touch): code, commands, error text, quoted text, file
  paths, URLs. Those are exact strings.

Full STE strips personality by design. Do not apply strict mode to prose that
needs a voice. A de-slop pass with no light mode is a footgun.

## The pass

1. Classify the text as strict, light, or exempt.
2. Run the linter on the draft:
   `python3 ~/.claude/skills/de-slopping/ste_lint.py <file>`, or pipe text on
   stdin.
3. Fix every `hard` finding. Judge each `soft` finding: keep it or cut it.
4. Apply the judgment rules below.
5. Re-run the linter. Confirm zero `hard` findings.
6. Send the clean text. Stay quiet about the edit unless asked for an audit.

## Rules the linter enforces (mechanical)

The linter counts words and matches patterns. It flags:

- Sentences over 25 words. Split them into numbered steps.
- The slop blocklist. Delete on sight:
  ```
  delve  crucial  seamless  comprehensive  robust  cutting-edge
  game-changer  tapestry  realm  plethora  myriad  elevate
  foster  streamline  meticulous  intricate  pivotal  testament
  ```
- One-word swaps:
  ```
  utilize, leverage        -> use      facilitate      -> help
  commence, initiate       -> start    terminate       -> stop
  prior to                 -> before   in order to     -> to
  additionally, moreover   -> also     approximately   -> about
  ```
- Stock hedges:
  ```
  it's important to note   it's worth mentioning
  when it comes to         at the end of the day
  ```
- Every em-dash. Use a comma, a colon, or a period.
- Soft modals (`should`, `would`, `may`, `might`): a soft flag. Keep `can`,
  `will`, `must`. They commit.
- Filler `-ing` such as `making it easy to`: a soft flag.

The linter matches exact forms. It flags `commence` but not `commencing`, and
`comprehensive` but not `comprehensively`. I catch those variants by judgment.

## Rules I apply (judgment)

- One word, one meaning. If a word reads two ways in context, replace it.
- One instruction per sentence. Sequences become numbered lists.
- Active voice. Name the agent: `The pump moves the fuel`.
- Condition before command. Write `If the flag is set, press enter`, not the
  reverse. The reader meets the condition first.
- Keep the small words. `the`, `a`, `that` stay. Short is not the same as
  broken.
- Preserve every fact. Add none. If a fact is missing, mark it
  `[value missing]`.

## What it refuses to do

- It does not delete facts to hit a word count. Forty facts in, forty out.
- It does not touch code, commands, or error strings. Those are exact.
- It does not invent a fact to finish a sentence. It marks the gap instead.

## Modes

- **Rewrite** (default): output the clean text. Keep every fact.
- **Audit**: output only the findings. Give rule, quoted text, and fix, one
  line each. Change nothing.
- **Light**: apply the slop, hedge, em-dash, and swap rules only. Keep the
  voice. Say that you used light mode.

## Example

**Before** (44 words, one sentence):

> In order to facilitate the seamless integration of the authentication
> module, it is important to note that developers should ensure that the
> configuration file has been comprehensively updated prior to commencing the
> deployment process, which can be accomplished via the CLI.

**After** (longest sentence 9 words):

> Update the configuration file before you start the deployment. Use the CLI
> to deploy. This connects the authentication module.

Same facts. A third of the words. No ambiguity.

## Attribution

Inspired by ASD-STE100 Simplified Technical English, maintained by the
AeroSpace and Defence Industries Association of Europe (ASD). This skill
applies its principles. It is not the official specification or its dictionary.
The specification is free at asd-ste100.org.
