import importlib.util
import unittest
from pathlib import Path

import numpy as np

TOOL = Path(__file__).resolve().parents[1] / "tools" / "inspect_ixelles_height_values.py"
SPEC = importlib.util.spec_from_file_location("inspect_ixelles_height_values", TOOL)
inspect = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(inspect)


class IxellesHeightValueDiagnosticsTest(unittest.TestCase):
    def test_paired_stats_excludes_unpaired_nodata(self):
        nodata = -9999.0
        dtm = np.array([[50.0, nodata, 52.0, 53.0]])
        dsm = np.array([[60.0, 61.0, nodata, 65.0]])
        stats = inspect.paired_stats(dsm, dtm, nodata, nodata)
        self.assertEqual(stats["paired_valid_count"], 2)
        self.assertEqual(stats["dtm"]["min"], 50.0)
        self.assertEqual(stats["dtm"]["max"], 53.0)
        self.assertEqual(stats["dsm_minus_dtm"]["p50"], 11.0)
        self.assertEqual(stats["dsm_minus_dtm"]["gt_0_5m_fraction"], 1.0)

    def test_zero_rasters_remain_visible_in_diagnostics(self):
        dsm = np.zeros((4, 4), dtype=float)
        dtm = np.zeros((4, 4), dtype=float)
        stats = inspect.paired_stats(dsm, dtm, None, None)
        self.assertEqual(stats["dtm"]["zero_fraction"], 1.0)
        self.assertEqual(stats["dsm"]["zero_fraction"], 1.0)
        self.assertEqual(stats["dsm_minus_dtm"]["near_zero_fraction"], 1.0)

    def test_no_paired_values_is_rejected(self):
        nodata = -9999.0
        dsm = np.array([[1.0, nodata]])
        dtm = np.array([[nodata, 2.0]])
        with self.assertRaisesRegex(ValueError, "No paired valid"):
            inspect.paired_stats(dsm, dtm, nodata, nodata)


if __name__ == "__main__":
    unittest.main()
