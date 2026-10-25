"""Static checks for the metric view artifact (ADR-003: seven KPIs,
one_to_many join, no invoker-dependent expressions)."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

MEASURES = ["net_revenue", "order_count", "average_order_value", "delivery_days",
            "late_delivery_rate", "return_rate", "discount_given"]


class MetricViewTest(unittest.TestCase):
    def setUp(self):
        self.sql = (ROOT / "sql" / "metric_views" / "20_mv_trading.sql").read_text()

    def test_yaml_11_and_source_is_header_fact(self):
        self.assertIn("version: 1.1", self.sql)
        self.assertIn("source: meridian_t02.gold.fct_orders", self.sql)

    def test_lines_join_is_one_to_many(self):
        self.assertIn("cardinality: one_to_many", self.sql)
        self.assertIn("on: source.order_key_hash = lines.order_key_hash", self.sql)

    def test_all_seven_kpis_present(self):
        for measure in MEASURES:
            self.assertIn(f"- name: {measure}", self.sql)

    def test_ratio_kpis_use_measure_composition_and_try_divide(self):
        self.assertIn("MEASURE(net_revenue), MEASURE(order_count)", self.sql)
        self.assertGreaterEqual(self.sql.count("try_divide("), 3)

    def test_no_invoker_dependent_expressions(self):
        for banned in ("current_user()", "is_member("):
            self.assertNotIn(banned, self.sql)

    def test_dimensions_cover_the_package_sheet(self):
        for dim in ("order_date", "order_month", "order_status",
                    "market_segment_at_order_time", "region_name", "nation_name"):
            self.assertIn(f"- name: {dim}", self.sql)


if __name__ == "__main__":
    unittest.main()
