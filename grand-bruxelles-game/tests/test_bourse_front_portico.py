from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HERO = ROOT / "data" / "urbis" / "heroes" / "bourse_lod2.game.json"
CAMERA = ROOT / "data" / "qa" / "photo_match" / "bourse_2019_geotagged_camera_evidence.json"
TOOL = ROOT / "tools" / "derive_bourse_front_portico.py"

spec = importlib.util.spec_from_file_location("derive_bourse_front_portico", TOOL)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


class BourseFrontPorticoTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        hero = json.loads(HERO.read_text(encoding="utf-8"))
        camera = json.loads(CAMERA.read_text(encoding="utf-8"))
        cls.report = module.derive(hero, camera)

    def test_source_and_heritage_semantics_are_explicit(self) -> None:
        report = self.report
        self.assertEqual(report["source_geometry"]["crs"], "EPSG:31370")
        self.assertEqual(
            report["source_geometry"]["package_sha256"],
            "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2",
        )
        self.assertEqual(report["heritage_semantics"]["column_count"], 6)
        self.assertEqual(report["heritage_semantics"]["stair"], "monumental")
        self.assertEqual(report["heritage_semantics"]["pediment"], "triangular")
        self.assertEqual(report["photo_witness"]["license"], "CC BY-SA 4.0")

    def test_front_band_is_non_degenerate_and_bounded_by_hero(self) -> None:
        plane = self.report["front_plane"]
        selection = self.report["selection"]
        self.assertGreater(selection["eligible_wall_triangle_count"], 0)
        self.assertGreater(selection["front_band_triangle_count"], 0)
        self.assertLessEqual(selection["front_band_triangle_count"], selection["eligible_wall_triangle_count"])
        self.assertGreater(plane["span_m"], 10.0)
        self.assertLess(plane["span_m"], 90.0)
        self.assertGreaterEqual(plane["y_min_m"], 0.0)
        self.assertLessEqual(plane["y_max_m"], 40.1553 + 1e-4)

    def test_camera_and_front_basis_are_unit_and_orthogonal(self) -> None:
        forward = self.report["to_camera_x_z"]
        tangent = self.report["front_tangent_x_z"]
        forward_len = (forward[0] ** 2 + forward[1] ** 2) ** 0.5
        tangent_len = (tangent[0] ** 2 + tangent[1] ** 2) ** 0.5
        dot = forward[0] * tangent[0] + forward[1] * tangent[1]
        self.assertAlmostEqual(forward_len, 1.0, places=9)
        self.assertAlmostEqual(tangent_len, 1.0, places=9)
        self.assertAlmostEqual(dot, 0.0, places=9)

    def test_no_runtime_claim_is_made_by_evidence_only_lot(self) -> None:
        self.assertFalse(self.report["runtime_approved"])
        self.assertFalse(self.report["realism_complete"])
        self.assertIn("six-column", self.report["next_gate"])


if __name__ == "__main__":
    unittest.main()
