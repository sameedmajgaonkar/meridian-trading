"""Local execution guard tests; these do not validate Databricks SQL semantics."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "phase0.py"
spec = importlib.util.spec_from_file_location("phase0", MODULE_PATH)
phase0 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phase0)


class Phase0Tests(unittest.TestCase):
    def test_rejects_missing_unbounded_and_non_calendar_windows(self):
        for start, end in [(None, None), ("1994-01-01", "1997-01-01"),
                           ("1994-06-01", "1995-06-01"), ("1995-01-01", "1994-01-01")]:
            with self.subTest(start=start, end=end), self.assertRaises(ValueError):
                phase0.validate_window(start, end)

    def test_dates_requires_explicit_scan_opt_in(self):
        args = phase0.parser().parse_args(["dates"])
        with self.assertRaises(ValueError):
            phase0.commands(args)

    def test_typed_parameters_are_passed_without_shell_interpolation(self):
        args = phase0.parser().parse_args(["profile", "--start", "1994-01-01", "--end", "1995-01-01"])
        for _, command in phase0.commands(args)[1:]:
            self.assertIn("start_date:DATE=1994-01-01", command)
            self.assertIn("end_date:DATE=1995-01-01", command)
            self.assertIn("sameed-dbx", command)

    def test_rejects_mutation_and_multiple_statements(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "unsafe.sql"
            for sql in ("CREATE TABLE t (id INT);", "SELECT 1; DROP TABLE t;",
                        "WITH a AS (SELECT 1) INSERT INTO t SELECT * FROM a;"):
                path.write_text("-- probe: bad\n" + sql)
                with self.subTest(sql=sql), self.assertRaises(ValueError):
                    phase0.load_probes(path)

    def test_dry_run_never_connects_or_writes(self):
        with patch.object(phase0.subprocess, "run") as run, patch.object(phase0.Path, "mkdir") as mkdir:
            with patch("builtins.print"):
                self.assertEqual(phase0.main(["inspect", "--dry-run"]), 0)
            run.assert_not_called()
            mkdir.assert_not_called()

    def run_mock_plan(self, results, stage="inspect"):
        with tempfile.TemporaryDirectory() as tmp:
            plan = [("current_user", ["databricks", "current-user", "me"]),
                    ("first_probe", ["databricks", "query"]),
                    ("second_probe", ["databricks", "query"])]
            with patch.object(phase0, "ROOT", Path(tmp)), patch.object(phase0, "commands", return_value=plan), \
                 patch.object(phase0.subprocess, "run", side_effect=results) as run, patch("builtins.print"):
                code = phase0.main([stage])
            manifest = next((Path(tmp) / "evidence" / "runs").glob("*/manifest.json"))
            return code, run.call_count, json.loads(manifest.read_text())

    def test_auth_failure_stops_before_sql_and_records_failure(self):
        result = subprocess.CompletedProcess([], 1, "", "OS keyring unreachable")
        code, calls, manifest = self.run_mock_plan([result])
        self.assertEqual((code, calls, manifest["complete"]), (1, 1, False))

    def test_failure_state_cannot_be_reported_as_pass(self):
        ok = subprocess.CompletedProcess([], 0, '{}', '')
        failed = subprocess.CompletedProcess([], 0, '{"state":"FAILED"}', '')
        code, calls, manifest = self.run_mock_plan([ok, failed])
        self.assertEqual((code, calls, manifest["complete"]), (1, 2, False))

    def test_capability_denial_does_not_skip_other_schemas(self):
        ok = subprocess.CompletedProcess([], 0, '{}', '')
        denied = subprocess.CompletedProcess([], 1, '', 'PERMISSION_DENIED')
        code, calls, manifest = self.run_mock_plan([ok, denied, ok], "capabilities")
        self.assertEqual((code, calls, manifest["complete"]), (1, 3, False))


if __name__ == "__main__":
    unittest.main()
