"""Unit tests for quality_gate.py using a lightweight fake Spark session."""

import sys
import unittest
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "quality_gate"))

import quality_gate


class FakeRow:
    def __init__(self, value):
        self.value = value

    def __getitem__(self, idx):
        return self.value


class FakeDataFrame:
    def __init__(self, rows):
        self._rows = [FakeRow(r) for r in rows]

    def collect(self):
        return self._rows


class FakeSpark:
    def __init__(self, query_responses=None, fail_write=False):
        self.responses = query_responses or {}
        self.fail_write = fail_write

    @property
    def read(self):
        return self

    def text(self, path):
        if path in self.responses:
            return FakeDataFrame([self.responses[path]])
        raise FileNotFoundError(f"Path not found: {path}")

    def sql(self, query):
        if self.fail_write and query.strip().startswith("INSERT INTO"):
            raise RuntimeError("Database write error")
        for k, v in self.responses.items():
            if k in query:
                return FakeDataFrame([v])
        return FakeDataFrame([0])


class QualityGateTest(unittest.TestCase):
    def test_missing_manifest_raises(self):
        spark = FakeSpark()
        with self.assertRaises((FileNotFoundError, ValueError)):
            quality_gate.read_manifests(spark, "/Volumes/test", 1)

    def test_empty_gold_produces_failing_check(self):
        # Query returns 1 when gold table is empty
        spark = FakeSpark(query_responses={"count(*) > 0": 1})
        name, status, _ = quality_gate.evaluate_check(
            "gold_orders_not_empty",
            "SELECT if(count(*) > 0, 0, 1) FROM gold.fct_orders",
            expected=0,
            tolerance=0,
            critical=True,
            spark=spark,
        )
        self.assertEqual(status, "FAIL")

    def test_failing_result_write_raises(self):
        spark = FakeSpark(fail_write=True)
        with self.assertRaises(RuntimeError):
            quality_gate.log_results(spark, "meridian_t02", 1, [("check1", "PASS", "0")])

    def test_kpi_tolerance_evaluation(self):
        spark_pass = FakeSpark(query_responses={"rev": "100.005"})
        _, status_pass, _ = quality_gate.evaluate_check(
            "net_revenue",
            "rev",
            expected=Decimal("100.00"),
            tolerance=Decimal("0.01"),
            critical=True,
            spark=spark_pass,
        )
        self.assertEqual(status_pass, "PASS")

        spark_fail = FakeSpark(query_responses={"rev": "100.05"})
        _, status_fail, _ = quality_gate.evaluate_check(
            "net_revenue",
            "rev",
            expected=Decimal("100.00"),
            tolerance=Decimal("0.01"),
            critical=True,
            spark=spark_fail,
        )
        self.assertEqual(status_fail, "FAIL")


if __name__ == "__main__":
    unittest.main()
