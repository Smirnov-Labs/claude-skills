#!/usr/bin/env python3
"""Tests for ste_lint. Written before the linter exists (RED phase).

Run: python3 test_ste_lint.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ste_lint import lint_text, exit_code  # noqa: E402


def rules(findings):
    return [f.rule for f in findings]


class TestMechanicalChecks(unittest.TestCase):
    def test_flags_em_dash(self):
        f = lint_text("Update the config — then deploy.")
        self.assertIn("em-dash", rules(f))
        self.assertEqual(1, exit_code(f))  # em-dash is a hard violation

    def test_flags_blocklist_word(self):
        f = lint_text("This is a seamless and robust solution.")
        self.assertIn("blocklist", rules(f))

    def test_flags_substitution_with_suggestion(self):
        f = lint_text("We utilize the cache to speed things up.")
        subs = [x for x in f if x.rule == "substitution"]
        self.assertTrue(subs)
        self.assertEqual("use", subs[0].suggestion)

    def test_flags_phrase_substitution(self):
        f = lint_text("Do this in order to warm the cache.")
        subs = [x for x in f if x.rule == "substitution"]
        self.assertTrue(any(x.suggestion == "to" for x in subs))

    def test_flags_stock_hedge(self):
        f = lint_text("It's important to note that the cache is warm.")
        self.assertIn("hedge", rules(f))

    def test_flags_soft_modal_as_soft(self):
        f = lint_text("This should work in most cases.")
        modals = [x for x in f if x.rule == "soft-modal"]
        self.assertTrue(modals)
        self.assertEqual("soft", modals[0].tier)
        self.assertEqual(0, exit_code(f))  # soft alone does not fail the gate

    def test_flags_long_sentence(self):
        long = "We " + "really " * 30 + "did it."  # 33 words, one sentence
        f = lint_text(long)
        self.assertIn("long-sentence", rules(f))

    def test_flags_filler_ing(self):
        f = lint_text("This library, making it easy to integrate, is nice.")
        self.assertIn("filler-ing", rules(f))


class TestExemptRegions(unittest.TestCase):
    """The linter must never flag slop that lives in code, quotes, URLs, or
    frontmatter. This is what lets the skill's own SKILL.md pass the linter."""

    def test_exempts_inline_code(self):
        f = lint_text("Call `utilize()` when ready.")
        self.assertEqual([], [x for x in f if x.rule == "substitution"])

    def test_exempts_fenced_code(self):
        text = "Text is fine.\n```\nwe utilize seamless robust foo\n```\n"
        self.assertEqual([], rules(lint_text(text)))

    def test_exempts_blockquote(self):
        f = lint_text("> In order to utilize the seamless robust thing.")
        self.assertEqual([], rules(f))

    def test_exempts_frontmatter(self):
        text = "---\ndescription: utilize seamless robust\n---\nClean line here.\n"
        self.assertEqual([], rules(lint_text(text)))

    def test_exempts_url(self):
        f = lint_text("See https://example.com/utilize-seamless for details.")
        self.assertEqual([], [x for x in f if x.rule in ("substitution", "blocklist")])


class TestClean(unittest.TestCase):
    def test_clean_text_passes(self):
        f = lint_text("Update the config before you deploy. Use the CLI.")
        self.assertEqual([], f)
        self.assertEqual(0, exit_code(f))


class TestVariants(unittest.TestCase):
    """Morphological variants are SOFT: flagged for review, never blocking."""

    def test_blocklist_adverb_variant_is_soft(self):
        f = lint_text("This comprehensively covers the cases.")
        v = [x for x in f if x.text.lower() == "comprehensively"]
        self.assertTrue(v, "expected 'comprehensively' to be flagged")
        self.assertEqual("soft", v[0].tier)
        self.assertEqual("blocklist", v[0].rule)

    def test_substitution_ing_variant_is_soft(self):
        f = lint_text("We are commencing the deployment now.")
        v = [x for x in f if x.text.lower() == "commencing"]
        self.assertTrue(v, "expected 'commencing' to be flagged")
        self.assertEqual("soft", v[0].tier)
        self.assertEqual("start", v[0].suggestion)

    def test_variants_do_not_fail_the_gate(self):
        f = lint_text("This comprehensively works.")
        self.assertEqual(0, exit_code(f))

    def test_no_false_positive_on_elevated(self):
        # 'elevate' is blocklist, but only its -ly form is derived, so the
        # legit technical word 'elevated' (elevated privileges) stays safe.
        f = lint_text("The user has elevated privileges.")
        self.assertEqual([], [x for x in f if x.text.lower() == "elevated"])


class TestLightMode(unittest.TestCase):
    """Light mode keeps the mode-independent slop (blocklist, hedges, swaps,
    em-dashes) and drops the strict-only rules (length, modals, filler)."""

    def test_light_mode_skips_sentence_length(self):
        long = "We " + "really " * 30 + "did it."
        f = lint_text(long, mode="light")
        self.assertNotIn("long-sentence", [x.rule for x in f])

    def test_light_mode_keeps_blocklist(self):
        f = lint_text("A seamless solution.", mode="light")
        self.assertIn("blocklist", [x.rule for x in f])

    def test_light_mode_keeps_hedge(self):
        f = lint_text("It's important to note the cache is warm.", mode="light")
        self.assertIn("hedge", [x.rule for x in f])

    def test_light_mode_skips_soft_modal(self):
        f = lint_text("This should work.", mode="light")
        self.assertNotIn("soft-modal", [x.rule for x in f])


if __name__ == "__main__":
    unittest.main()
