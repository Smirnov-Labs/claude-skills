#!/usr/bin/env python3
"""ste_lint - flag AI-slop and STE violations in Markdown prose.

The *mechanical half* of the de-slopping skill: the countable rules a regex can
enforce without judgment. The judgment rules (one word/one meaning, preserving
every fact) stay with the model.

Rules live in rules.json next to this file. Edit that to tune the word lists.

Tiers:
  hard  - unambiguous slop; makes the tool exit non-zero (hook-ready)
  soft  - a flag for review; the model decides whether it is a real violation.
          Morphological variants (commence -> commencing) are always soft.

Modes:
  strict (default) - every rule. For deliverables a reader acts on.
  light            - only the mode-independent slop: blocklist, substitutions,
                     hedges, em-dashes. Drops length, modals, filler, passive.
                     For voiced prose that must keep its rhythm.

Exempt regions (never flagged): fenced code, inline code, blockquotes, URLs,
and YAML frontmatter. This is what lets the skill's own SKILL.md pass clean.

Usage:
  python3 ste_lint.py FILE [FILE ...]        # lint files (strict)
  python3 ste_lint.py --mode light FILE      # voiced-prose ruleset
  python3 ste_lint.py --json FILE            # machine-readable (for a hook)
  python3 ste_lint.py < draft.md             # read stdin
"""
import argparse
import json
import os
import re
import sys
from collections import namedtuple

Finding = namedtuple("Finding", "line col tier rule text suggestion")

# --- Rule data (loaded from rules.json) --------------------------------------

_RULES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rules.json")
with open(_RULES_PATH, encoding="utf-8") as _fh:
    _RULES = json.load(_fh)

BLOCKLIST = set(_RULES["blocklist"])          # single words, deleted on sight
SUBSTITUTIONS = dict(_RULES["substitutions"])  # word -> plain replacement
PHRASE_SUBS = dict(_RULES["phrase_subs"])      # multi-word slop -> replacement
SOFT_MODALS = set(_RULES["soft_modals"])       # should/would/may/might
HEDGES = list(_RULES["hedges"])                # regex fragments
FILLER_ING = list(_RULES["filler_ing"])        # regex fragments

PASSIVE = re.compile(
    r"\b(?:is|are|was|were|be|been|being)\s+"
    r"(?:\w+ed|done|made|given|taken|shown|written|built|updated|created|"
    r"removed|added|deleted)\b",
    re.I,
)
STRUCT = re.compile(r"^\s*(?:[-*+]\s|\d+[.)]\s|#{1,6}\s|\|)")
TOKEN = re.compile(r"\b[\w-]+\b")


def _adverb(base):
    """comprehensive -> comprehensively. Nonsense forms (delve -> delvely)
    are harmless: they never appear in real text."""
    return base + "ly"


def _verb_forms(base):
    """commence -> {commences, commencing, commenced}. Used only for
    substitution verbs, whose inflections are reliably slop."""
    forms = {base + "s"}
    if base.endswith(("s", "x", "z", "ch", "sh")):
        forms.add(base + "es")
    if base.endswith("e"):
        forms.add(base[:-1] + "ing")
        forms.add(base + "d")
    else:
        forms.add(base + "ing")
        forms.add(base + "ed")
    return forms


def _build_variants():
    """Map derived form -> (rule, suggestion), all SOFT. A form that collides
    with a HARD base is skipped, so explicit entries never get downgraded.

    Blocklist gets only the adverb (-ly): safe, because -ed/-ing forms of
    blocklist verbs (elevate -> elevated) have legit technical uses.
    Substitutions get verb inflections, whose replacement is the lemma."""
    variants = {}
    for w in BLOCKLIST:
        form = _adverb(w)
        if form not in BLOCKLIST and form not in SUBSTITUTIONS:
            variants.setdefault(form, ("blocklist", "delete"))
    for w, rep in SUBSTITUTIONS.items():
        for form in _verb_forms(w):
            if form not in BLOCKLIST and form not in SUBSTITUTIONS:
                variants.setdefault(form, ("substitution", rep))
    return variants


VARIANTS = _build_variants()

# --- Masking (exempt regions) ------------------------------------------------


def _mask(m):
    """Replace a span with spaces so line/column offsets stay exact."""
    return " " * (m.end() - m.start())


def mask_spans(line):
    """Blank out inline code and URLs on an otherwise-prose line."""
    line = re.sub(r"`[^`]*`", _mask, line)
    line = re.sub(r"https?://\S+", _mask, line)
    return line


def _frontmatter_end(lines):
    if not lines or lines[0].strip() != "---":
        return -1
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return i
    return -1


def _mask_document(text):
    """Per-line masked text: exempt lines become blank, prose lines keep their
    words with code/URLs blanked. Line numbers are preserved."""
    lines = text.splitlines()
    fm_end = _frontmatter_end(lines)
    in_fence = False
    masked = []
    for idx, raw in enumerate(lines):
        stripped = raw.lstrip()
        exempt = idx <= fm_end
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            exempt = True
        elif in_fence:
            exempt = True
        elif stripped.startswith(">"):
            exempt = True  # blockquote: quoted text is exact, leave it alone
        masked.append(" " * len(raw) if exempt else mask_spans(raw))
    return masked


# --- Checks ------------------------------------------------------------------


def _check_line(line, lineno, out, mode):
    for m in re.finditer("—", line):  # em-dash
        out.append(Finding(lineno, m.start() + 1, "hard", "em-dash",
                           "—", "comma, colon, or period"))

    for m in TOKEN.finditer(line):
        w = m.group(0).lower()
        col = m.start() + 1
        if w in BLOCKLIST:
            out.append(Finding(lineno, col, "hard", "blocklist", m.group(0), "delete"))
        elif w in SUBSTITUTIONS:
            out.append(Finding(lineno, col, "hard", "substitution",
                               m.group(0), SUBSTITUTIONS[w]))
        elif mode == "strict" and w in SOFT_MODALS:
            out.append(Finding(lineno, col, "soft", "soft-modal",
                               m.group(0), "cut, or commit with can/will/must"))
        elif w in VARIANTS:
            rule, suggestion = VARIANTS[w]
            out.append(Finding(lineno, col, "soft", rule, m.group(0), suggestion))

    for phrase, rep in PHRASE_SUBS.items():
        for m in re.finditer(r"\b" + re.escape(phrase) + r"\b", line, re.I):
            out.append(Finding(lineno, m.start() + 1, "hard", "substitution",
                               m.group(0), rep))

    for pat in HEDGES:
        for m in re.finditer(pat, line, re.I):
            out.append(Finding(lineno, m.start() + 1, "hard", "hedge",
                               m.group(0), "delete"))

    if mode != "strict":
        return  # light mode stops here: no filler/passive/length/modals

    for pat in FILLER_ING:
        for m in re.finditer(pat, line, re.I):
            out.append(Finding(lineno, m.start() + 1, "soft", "filler-ing",
                               m.group(0), "name the verb, drop the -ing"))

    for m in PASSIVE.finditer(line):
        out.append(Finding(lineno, m.start() + 1, "soft", "passive",
                           m.group(0), "use active voice"))


def _split_sentences(text):
    return [s for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()]


def _check_sentences(masked, out):
    """Length-check prose paragraphs. Structural and blank lines flush and are
    skipped, so lists and tables never inflate a sentence's word count."""
    para = []
    start = None

    def flush():
        if not para:
            return
        blob = " ".join(para).strip()
        for sent in _split_sentences(blob):
            n = len(sent.split())
            snippet = sent[:57] + "..." if len(sent) > 60 else sent
            if n > 25:
                out.append(Finding(start, 1, "hard", "long-sentence",
                                   snippet, "%d words; split into steps" % n))
            elif n >= 20:
                out.append(Finding(start, 1, "soft", "long-sentence",
                                   snippet, "%d words; tighten" % n))

    for idx, line in enumerate(masked):
        if line.strip() == "" or STRUCT.match(line):
            flush()
            para, start = [], None
            continue
        if start is None:
            start = idx + 1
        para.append(line)
    flush()


def lint_text(text, filename="<stdin>", mode="strict"):
    masked = _mask_document(text)
    findings = []
    for idx, line in enumerate(masked):
        _check_line(line, idx + 1, findings, mode)
    if mode == "strict":
        _check_sentences(masked, findings)
    findings.sort(key=lambda f: (f.line, f.col))
    return findings


def exit_code(findings):
    return 1 if any(f.tier == "hard" for f in findings) else 0


# --- CLI ---------------------------------------------------------------------


def _print_human(items):
    if not items:
        print("clean: 0 findings")
        return
    for name, f in items:
        tag = "HARD" if f.tier == "hard" else "soft"
        arrow = "  -> %s" % f.suggestion if f.suggestion else ""
        print("%s:%d:%d  [%s %s]  «%s»%s"
              % (name, f.line, f.col, tag, f.rule, f.text, arrow))
    hard = sum(1 for _, f in items if f.tier == "hard")
    print("\n%d hard, %d soft" % (hard, len(items) - hard))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("paths", nargs="*", help="files to lint; omit to read stdin")
    ap.add_argument("--mode", choices=["strict", "light"], default="strict",
                    help="strict (default) or light (voiced prose)")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args(argv)

    inputs = []
    if args.paths:
        for p in args.paths:
            with open(p, encoding="utf-8") as fh:
                inputs.append((p, fh.read()))
    else:
        inputs.append(("<stdin>", sys.stdin.read()))

    items = []
    for name, text in inputs:
        for f in lint_text(text, name, args.mode):
            items.append((name, f))

    if args.json:
        print(json.dumps([dict(file=n, **f._asdict()) for n, f in items], indent=2))
    else:
        _print_human(items)

    return 1 if any(f.tier == "hard" for _, f in items) else 0


if __name__ == "__main__":
    sys.exit(main())
