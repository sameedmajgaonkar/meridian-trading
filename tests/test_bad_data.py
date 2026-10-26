"""Unit tests for landing batch plan, segment cycle, and injection rules."""

import unittest
import batch_plan as bad_data


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
        self.assertEqual(b2_changes, keys[:2])
        self.assertEqual(b3_changes, keys[:2])


if __name__ == "__main__":
    unittest.main()
