"""Failures remain diagnostic rows instead of disappearing on SQL errors."""
import unittest
from types import SimpleNamespace

import quality_gate as gate


class GateTests(unittest.TestCase):
    def test_pass_failure_null_and_sql_error(self):
        def query(sql):
            if sql == "error":
                raise RuntimeError("SQL failed")
            return SimpleNamespace(first=lambda: [{"pass": 0, "fail": 1, "null": None}[sql]])
        result = gate.evaluate_checks(SimpleNamespace(sql=query), [(x, x) for x in ("pass", "fail", "null", "error")], "meridian_t02_dev", 1)
        self.assertEqual([r[1] for r in result], ["PASSED", "FAILED", "ERROR", "ERROR"])
        self.assertIn("SQL failed", result[-1][3])


if __name__ == "__main__":
    unittest.main()
