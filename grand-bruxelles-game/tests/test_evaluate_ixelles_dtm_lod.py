import importlib.util
import unittest
from pathlib import Path

import numpy as np
from affine import Affine

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "evaluate_ixelles_dtm_lod.py"
spec = importlib.util.spec_from_file_location("evaluate_ixelles_dtm_lod", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


class IxellesDtmLodTests(unittest.TestCase):
    def test_cell_bbox_parses_500m_epsg31370_grid(self):
        self.assertEqual(
            module.cell_bbox("bxl-e149000-n169000-s500"),
            (149000.0, 169000.0, 149500.0, 169500.0),
        )

    def test_bilinear_sampling_preserves_planar_surface(self):
        transform = Affine(0.5, 0.0, 149000.0, 0.0, -0.5, 169500.0)
        rows, cols = np.meshgrid(np.arange(1000), np.arange(1000), indexing="ij")
        xs = transform.c + (cols + 0.5) * transform.a
        ys = transform.f + (rows + 0.5) * transform.e
        surface = 70.0 + 0.01 * (xs - 149000.0) + 0.02 * (ys - 169000.0)
        cell = module.evaluate_cell(surface.astype(np.float64), transform, "bxl-e149000-n169000-s500", (1.0, 2.0, 4.0))
        for level in cell["levels"]:
            self.assertLess(level["rmse_m"], 1e-8)
            self.assertLess(level["p95_abs_error_m"], 1e-8)

    def test_coarser_grid_exposes_localized_terrain_error(self):
        transform = Affine(0.5, 0.0, 149000.0, 0.0, -0.5, 169500.0)
        rows, cols = np.meshgrid(np.arange(1000), np.arange(1000), indexing="ij")
        xs = transform.c + (cols + 0.5) * transform.a
        ys = transform.f + (rows + 0.5) * transform.e
        base = 75.0 + 0.004 * (xs - 149000.0)
        bump = 4.0 * np.exp(-(((xs - 149250.0) ** 2 + (ys - 169250.0) ** 2) / (2 * 3.0 ** 2)))
        terrain = base + bump
        cell = module.evaluate_cell(terrain.astype(np.float64), transform, "bxl-e149000-n169000-s500", (1.0, 8.0))
        fine, coarse = cell["levels"]
        self.assertGreater(coarse["max_abs_error_m"], fine["max_abs_error_m"])
        self.assertGreater(coarse["rmse_m"], fine["rmse_m"])

    def test_error_metrics_reject_no_paired_samples(self):
        source = np.asarray([np.nan, np.nan])
        reconstructed = np.asarray([1.0, 2.0])
        with self.assertRaises(ValueError):
            module.error_metrics(source, reconstructed)

    def test_invalid_cell_size_is_rejected(self):
        with self.assertRaises(ValueError):
            module.cell_bbox("bxl-e149000-n169000-s250")


if __name__ == "__main__":
    unittest.main()
