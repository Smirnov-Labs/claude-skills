#!/usr/bin/env python3
"""Tests for the slop_guard Stop hook. Written before the hook (RED phase).

Run: python3 hooks/test_slop_guard.py
"""
import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from slop_guard import evaluate  # noqa: E402


class TestEvaluate(unittest.TestCase):
    def test_blocks_on_hedge(self):
        d = evaluate({"last_assistant_message":
                      "It's important to note the cache is warm."})
        self.assertIsNotNone(d)
        self.assertEqual("block", d["decision"])
        self.assertIn("important to note", d["reason"].lower())

    def test_allows_clean_message(self):
        d = evaluate({"last_assistant_message": "Update the config, then deploy."})
        self.assertIsNone(d)

    def test_loop_guard_allows_when_active(self):
        d = evaluate({"last_assistant_message": "It's important to note this.",
                      "stop_hook_active": True})
        self.assertIsNone(d)

    def test_default_does_not_block_domain_terms(self):
        # 'realm' and 'robust' are hard blocklist words, but the default block
        # set is hedges only, so legit technical vocabulary never blocks.
        d = evaluate({"last_assistant_message":
                      "The Keycloak realm uses a robust config."})
        self.assertIsNone(d)

    def test_env_widening_blocks_blocklist(self):
        d = evaluate({"last_assistant_message": "A seamless design."},
                     block_rules={"blocklist"})
        self.assertIsNotNone(d)

    def test_empty_or_missing_message_allows(self):
        self.assertIsNone(evaluate({"last_assistant_message": ""}))
        self.assertIsNone(evaluate({}))

    def test_cli_blocks_via_stdout_json(self):
        payload = json.dumps({"last_assistant_message":
                              "At the end of the day, ship it."})
        p = subprocess.run([sys.executable, os.path.join(HERE, "slop_guard.py")],
                           input=payload, capture_output=True, text=True)
        self.assertEqual(0, p.returncode)  # Stop hooks block via exit 0 + JSON
        out = json.loads(p.stdout)
        self.assertEqual("block", out["decision"])

    def test_cli_allows_clean_via_empty_stdout(self):
        payload = json.dumps({"last_assistant_message": "Ship the config change."})
        p = subprocess.run([sys.executable, os.path.join(HERE, "slop_guard.py")],
                           input=payload, capture_output=True, text=True)
        self.assertEqual(0, p.returncode)
        self.assertEqual("", p.stdout.strip())  # no decision => stop proceeds


if __name__ == "__main__":
    unittest.main()
