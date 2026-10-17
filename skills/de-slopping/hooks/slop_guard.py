#!/usr/bin/env python3
"""Stop hook: block the turn if my final reply contains information-free slop.

Reads the Stop event JSON on stdin, lints `last_assistant_message` in light
mode, and blocks (decision: block) if any finding matches the block set.

The block set defaults to hedges only: phrases like "it's important to note"
that are slop in every context. Blocklist words are excluded by default, because
domain terms (realm, robust) are legitimate here and would false-block. Widen
the set with SLOP_GUARD_BLOCK_RULES, a comma list of rule names, for example:

    SLOP_GUARD_BLOCK_RULES="hedge,blocklist,substitution,em-dash"

Contract (Claude Code Stop hook): exit 0 and print {"decision":"block",
"reason":...} to block. Omit the decision to let the stop proceed. Respect
`stop_hook_active` to avoid loops (it caps at 8 blocks). Fail open on any error:
a broken hook must never wedge the session.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ste_lint import lint_text  # noqa: E402

DEFAULT_BLOCK_RULES = frozenset({"hedge"})


def _block_rules():
    raw = os.environ.get("SLOP_GUARD_BLOCK_RULES", "")
    chosen = {r.strip() for r in raw.split(",") if r.strip()}
    return chosen or DEFAULT_BLOCK_RULES


def _reason(hits):
    items = "; ".join("«%s» (%s)" % (f.text, f.rule) for f in hits[:8])
    return ("Your reply contains slop the de-slopping skill blocks: %s. "
            "Remove or rephrase it, keep every fact, then finish." % items)


def evaluate(payload, block_rules=None):
    """Return a block-decision dict, or None to allow the stop."""
    if payload.get("stop_hook_active"):
        return None  # already continuing from a prior block: do not loop
    message = (payload.get("last_assistant_message") or "").strip()
    if not message:
        return None
    rules = block_rules if block_rules is not None else _block_rules()
    hits = [f for f in lint_text(message, mode="light") if f.rule in rules]
    if not hits:
        return None
    return {"decision": "block", "reason": _reason(hits)}


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0  # fail open
    decision = evaluate(payload)
    if decision:
        print(json.dumps(decision))
    return 0


if __name__ == "__main__":
    sys.exit(main())
