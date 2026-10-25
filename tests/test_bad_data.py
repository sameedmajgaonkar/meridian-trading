"""Unit tests for landing batch plan, segment cycle, and injection rules."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "landing"))

import bad_data


class BadDataTests(unittest.TestCase):
    def test_batches_cover_window_without_gaps(self):
        b1 = bad_data.BATCHES[1]
        b2 = bad_data.BATCHES[2]
        b3 = bad_data.BATCHES[3]
        self.assertEqual(b1["start"], "1995-01-01")
        self.assertEqual(b1["end"], b2["start"])
        self.assertEqual(b2["end"], b3["start"])
        self.assertEqual(b3["end"], "1996-01-01")

    def test_segment_cycle(self):
        cur = "AUTOMOBILE"
        for _ in range(5):
            cur = bad_data.NEXT_SEGMENT[cur]
        self.assertEqual(cur, "AUTOMOBILE")

        keys = list(range(1, 20))
        b2_changes = bad_data.get_segment_changes(2, keys)
        b3_changes = bad_data.get_segment_changes(3, keys)
        self.assertEqual(len(b2_changes), 5)
        self.assertEqual(len(b3_changes), 7)
        self.assertEqual(b3_changes[-2:], keys[:2])

    def test_rules_have_name_and_predicate(self):
        for name, pred, _ in bad_data.ORDERS_RULES + bad_data.LINEITEM_RULES:
            self.assertTrue(name)
            self.assertTrue(pred.startswith("rn = "))


if __name__ == "__main__":
    unittest.main()
