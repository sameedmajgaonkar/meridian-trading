"""Batch progression and retry tests need no Spark runtime."""
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

from simulate import freeze_budget, resolve_batch, write_batch


class LandingTests(unittest.TestCase):
    def test_headers_alone_do_not_advance_and_completed_replay_skips(self):
        with tempfile.TemporaryDirectory() as volume:
            df = SimpleNamespace(write=Mock())
            path = f"{volume}/orders/batch=1"
            write_batch(df, path)
            write_batch(df, path)
            df.write.mode.return_value.parquet.assert_called_once_with(path)
            self.assertEqual(resolve_batch(volume, "next"), 1)
            with self.assertRaises(ValueError):
                resolve_batch(volume, "2")
            (Path(volume) / "_completed" / "batch=1").touch()
            self.assertEqual(resolve_batch(volume, "next"), 2)
            self.assertEqual(resolve_batch(volume, "1"), 1)
            with self.assertRaises(ValueError):
                resolve_batch(volume, "4")

    def test_only_our_interrupted_write_can_be_replaced(self):
        with tempfile.TemporaryDirectory() as volume:
            path = Path(volume) / "lineitem" / "batch=1"
            path.mkdir(parents=True)
            df = SimpleNamespace(write=Mock())
            with self.assertRaises(RuntimeError):
                write_batch(df, str(path))
            markers = Path(volume) / "_completed"
            (markers / "lineitem.batch=1.started").touch()
            df.write.mode.return_value.parquet.side_effect = [RuntimeError("interrupted"), None]
            with self.assertRaises(RuntimeError):
                write_batch(df, str(path))
            self.assertFalse((markers / "lineitem.batch=1").exists())
            write_batch(df, str(path))
            self.assertTrue((markers / "lineitem.batch=1").exists())

    def test_budget_cannot_change_mid_replay(self):
        with tempfile.TemporaryDirectory() as volume:
            freeze_budget(volume, 2000)
            freeze_budget(volume, 2000)
            with self.assertRaises(ValueError):
                freeze_budget(volume, 1)


if __name__ == "__main__":
    unittest.main()
