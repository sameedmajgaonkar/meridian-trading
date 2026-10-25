"""Unit tests for the deterministic landing plan (src/landing/bad_data.py).

Pure Python tests runnable locally with stdlib unittest.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "landing"))

import bad_data


class BatchPlanTest(unittest.TestCase):
    def test_batches_cover_the_year_without_gaps(self):
        b1 = bad_data.BATCHES[1]
        b2 = bad_data.BATCHES[2]
        b3 = bad_data.BATCHES[3]
        self.assertEqual(b1["start"], "1995-01-01")
        self.assertEqual(b1["end"], b2["start"])
        self.assertEqual(b2["end"], b3["start"])
        self.assertEqual(b3["end"], "1996-01-01")

    def test_snapshot_dates_are_ordered_and_within_window(self):
        dates = [bad_data.BATCHES[b]["snapshot_date"] for b in (1, 2, 3)]
        self.assertEqual(dates, sorted(dates))
        self.assertTrue(all(d.startswith("1995-") for d in dates))


class SegmentChangeTest(unittest.TestCase):
    def test_cyclic_successor(self):
        self.assertEqual(bad_data.segment_after("AUTOMOBILE"), "BUILDING")
        self.assertEqual(bad_data.segment_after("MACHINERY"), "AUTOMOBILE")

    def test_two_customers_reach_three_versions(self):
        keys = list(range(100, 120))
        b2_changes = bad_data.segment_changes(2, keys)
        b3_changes = bad_data.segment_changes(3, keys)
        self.assertEqual(len(b2_changes), 5)
        self.assertEqual(len(b3_changes), 7)  # 5 new + 2 repeat

        b2_keys = {k for k, _ in b2_changes}
        b3_repeat_keys = {k for k, v in b3_changes if v == 2}
        self.assertEqual(len(b3_repeat_keys), 2)
        self.assertTrue(b3_repeat_keys.issubset(b2_keys))

    def test_batch_1_makes_no_changes(self):
        keys = list(range(100, 120))
        self.assertEqual(bad_data.segment_changes(1, keys), [])


class RuleTest(unittest.TestCase):
    def test_rules_have_names_and_sampled_predicates(self):
        for rules in (bad_data.ORDERS_RULES, bad_data.LINEITEM_RULES):
            for name, pred, action in rules:
                self.assertTrue(name)
                self.assertIn("% 25000", pred)
                if action is not None:
                    col, repl = action
                    self.assertTrue(col and repl)

    def test_early_order_plan(self):
        self.assertGreaterEqual(bad_data.EARLY_ORDER_LIMIT, 1)
        self.assertIn("% 25000", bad_data.EARLY_ORDER_PREDICATE)


if __name__ == "__main__":
    unittest.main()
