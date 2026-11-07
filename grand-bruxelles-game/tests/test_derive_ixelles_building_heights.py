import importlib.util
import tempfile
import unittest
from pathlib import Path

import numpy as np

TOOL = Path(__file__).resolve().parents[1] / "tools" / "derive_ixelles_building_heights.py"
SPEC = importlib.util.spec_from_file_location("derive_ixelles_building_heights", TOOL)
derive = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(derive)


class IxellesBuildingHeightStatsTest(unittest.TestCase):
    def test_robust_percentiles_are_recorded_without_baking_one_height(self):
        dtm = np.full(100, 50.0)
        dsm = dtm + np.arange(100, dtype=float) / 10.0
        stats = derive.summarize_height_samples(dsm, dtm, None, None)
        self.assertEqual(stats["pixel_count_valid"], 100)
        self.assertEqual(stats["confidence"], "high")
        self.assertAlmostEqual(stats["plausible_difference_m"]["p50"], 4.95, places=2)
        self.assertAlmostEqual(stats["plausible_difference_m"]["p75"], 7.425, places=3)
        self.assertAlmostEqual(stats["plausible_difference_m"]["p90"], 8.91, places=2)

    def test_nodata_and_suspicious_samples_remain_auditable(self):
        nodata = -9999.0
        dtm = np.array([50.0, 50.0, 50.0, 50.0, nodata, 50.0])
        dsm = np.array([60.0, 49.0, 400.0, 61.0, 60.0, nodata])
        stats = derive.summarize_height_samples(dsm, dtm, nodata, nodata)
        self.assertEqual(stats["pixel_count_valid"], 4)
        self.assertEqual(stats["pixel_count_plausible"], 2)
        self.assertEqual(stats["negative_below_noise_count"], 1)
        self.assertEqual(stats["over_250m_count"], 1)
        self.assertEqual(stats["confidence"], "insufficient")
        self.assertEqual(stats["plausible_difference_m"]["p50"], 10.5)

    def test_shape_mismatch_is_rejected(self):
        with self.assertRaises(ValueError):
            derive.summarize_height_samples(np.zeros(3), np.zeros(4), None, None)

    def test_tiny_footprint_never_claims_high_confidence(self):
        dtm = np.full(8, 50.0)
        dsm = np.full(8, 62.0)
        stats = derive.summarize_height_samples(dsm, dtm, None, None)
        self.assertEqual(stats["pixel_count_plausible"], 8)
        self.assertEqual(stats["confidence"], "insufficient")

    def test_degenerate_zero_mosaics_are_rejected_before_height_evidence(self):
        dtm = np.zeros((32, 32), dtype=float)
        dsm = np.zeros((32, 32), dtype=float)
        with self.assertRaisesRegex(ValueError, "degenerate"):
            derive.validate_height_mosaics(dsm, dtm, None, None)

    def test_mosaic_quality_uses_only_pixels_valid_in_both_rasters(self):
        nodata = -9999.0
        dtm = np.array([[50.0, nodata, 52.0, 53.0]])
        dsm = np.array([[60.0, 61.0, nodata, 65.0]])
        diagnostics = derive.validate_height_mosaics(
            dsm,
            dtm,
            nodata,
            nodata,
            min_dtm_range_m=0.1,
            min_positive_height_fraction=0.5,
        )
        self.assertEqual(diagnostics["valid_sample_count"], 2)
        self.assertEqual(diagnostics["dtm_min_m"], 50.0)
        self.assertEqual(diagnostics["dtm_max_m"], 53.0)
        self.assertEqual(diagnostics["height_p50_m"], 11.0)
        self.assertEqual(diagnostics["identical_dsm_dtm_fraction"], 0.0)

    def test_open_mosaic_preserves_values_with_extreme_float32_nodata(self):
        import rasterio
        from rasterio.transform import from_origin

        nodata = np.float32(-3.4028234663852886e38)
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            paths = []
            for i, (north, values) in enumerate(((2.0, [[60.0, 61.0], [62.0, 63.0]]), (4.0, [[70.0, 71.0], [72.0, 73.0]]))):
                path = root / f"tile-{i}.tif"
                with rasterio.open(
                    path,
                    "w",
                    driver="GTiff",
                    width=2,
                    height=2,
                    count=1,
                    dtype="float32",
                    transform=from_origin(0.0, north, 1.0, 1.0),
                    nodata=float(nodata),
                ) as dst:
                    dst.write(np.asarray(values, dtype=np.float32), 1)
                paths.append(path)
            mosaic, _transform, out_nodata = derive.open_mosaic(paths)
            self.assertEqual(mosaic.shape, (4, 2))
            self.assertTrue(np.isnan(out_nodata))
            self.assertAlmostEqual(float(np.nanmin(mosaic)), 60.0)
            self.assertAlmostEqual(float(np.nanmax(mosaic)), 73.0)
            self.assertGreater(float(np.nanmax(mosaic) - np.nanmin(mosaic)), 10.0)

    def test_realistic_mosaic_variation_passes_quality_gate(self):
        x = np.linspace(55.0, 62.0, 32)
        dtm = np.repeat(x[np.newaxis, :], 32, axis=0)
        dsm = dtm.copy()
        dsm[8:24, 8:24] += 14.0
        diagnostics = derive.validate_height_mosaics(dsm, dtm, None, None)
        self.assertGreater(diagnostics["dtm_range_m"], 5.0)
        self.assertGreater(diagnostics["positive_height_fraction"], 0.1)
        self.assertGreater(diagnostics["height_p95_m"], 10.0)


if __name__ == "__main__":
    unittest.main()
