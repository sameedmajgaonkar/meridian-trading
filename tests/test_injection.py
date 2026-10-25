"""Unit tests for the deterministic landing plan (src/landing/injection.py).

No Databricks dependency: the injection plan is pure Python on purpose so the
whole batch plan is testable locally before anything is deployed.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "landing"))

import injection


class ShardTest(unittest.TestCase):
    def test_shards_are_disjoint_and_cover_the_whole_window(self):
        spans = [injection.shard_range("1995-01-01", b) for b in (1, 2, 3)]
        self.assertEqual(spans[0], ("1995-01-01", "1995-05-01"))
        self.assertEqual(spans[1], ("1995-05-01", "1995-09-01"))
        self.assertEqual(spans[2], ("1995-09-01", "1996-01-01"))
        # end-exclusive chain: no gap, no overlap, window end reached
        self.assertEqual(spans[0][1], spans[1][0])
        self.assertEqual(spans[1][1], spans[2][0])
        self.assertEqual(spans[2][1], "1996-01-01")

    def test_effective_dates_are_inside_the_window_and_ordered(self):
        dates = [injection.BATCH_EFFECTIVE_DATES[b] for b in (1, 2, 3)]
        self.assertEqual(dates, sorted(dates))
        self.assertEqual(dates[0], "1995-01-01")
        self.assertTrue(all("1995" in d for d in dates))


class SegmentChangeTest(unittest.TestCase):
    def test_cyclic_successor(self):
        self.assertEqual(injection.segment_after("AUTOMOBILE"), "BUILDING")
        self.assertEqual(injection.segment_after("MACHINERY"), "AUTOMOBILE")

    def test_two_customers_reach_three_versions(self):
        once = {k for b in (2, 3) for k, n in injection.changes_for_batch(b) if n == 1}
        twice = {k for b in (2, 3) for k, n in injection.changes_for_batch(b) if n == 2}
        self.assertEqual(len(twice), 2)
        self.assertTrue(twice.issubset(once))
        self.assertGreaterEqual(len(once - twice), 3)

    def test_batch_1_makes_no_changes(self):
        self.assertEqual(injection.changes_for_batch(1), [])


class RuleTest(unittest.TestCase):
    def test_rules_have_names_predicates_and_valid_actions(self):
        for rules in (injection.ORDERS_RULES, injection.LINEITEM_RULES,
                      injection.CUSTOMER_RULES):
            for name, pred, action in rules:
                self.assertTrue(name)
                self.assertIn("%", pred)
                if action is not None:
                    col, repl = action
                    self.assertTrue(col and repl)

    def test_expected_rule_count_math(self):
        # predicates are `key % modulus == residue`; the helper mirrors that
        keys = list(range(1, 101))
        self.assertEqual(sum(1 for k in keys if k % 10 == 3), 10)
        self.assertEqual(sum(1 for k in keys if k % 97 == 3), 2)

    def test_early_order_plan(self):
        self.assertGreaterEqual(injection.EARLY_ORDER_LIMIT, 1)
        self.assertIn("%", injection.EARLY_ORDER_PREDICATE)


if __name__ == "__main__":
    unittest.main()
