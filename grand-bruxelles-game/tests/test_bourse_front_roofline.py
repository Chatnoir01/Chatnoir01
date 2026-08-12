from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HERO = ROOT / "data" / "urbis" / "heroes" / "bourse_lod2.game.json"
CANDIDATE = ROOT / "data" / "qa" / "bourse_portico_articulation_candidate.json"
TOOL = ROOT / "tools" / "analyze_bourse_front_roofline.py"

spec = importlib.util.spec_from_file_location("analyze_bourse_front_roofline", TOOL)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


class BourseFrontRooflineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        hero = json.loads(HERO.read_text(encoding="utf-8"))
        candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        cls.report = module.analyze(hero, candidate)

    def test_source_and_heritage_contract_remain_locked(self) -> None:
        self.assertEqual(self.report["hero_id"], "bourse")
        self.assertEqual(self.report["source_crs"], "EPSG:31370")
        self.assertEqual(
            self.report["source_package_sha256"],
            "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2",
        )
        self.assertIn("six Corinthian columns", self.report["heritage_fact"])
        self.assertIn("triangular pediment", self.report["heritage_fact"])

    def test_front_basis_is_same_reviewed_portico_basis(self) -> None:
        basis = self.report["front_basis"]
        self.assertAlmostEqual(basis["tangent_min_m"], -18.231126974238453, places=6)
        self.assertAlmostEqual(basis["tangent_max_m"], 13.347734117571157, places=6)
        self.assertGreater(basis["entablature_top_y_m"], 19.0)
        self.assertLess(basis["entablature_top_y_m"], 22.0)

    def test_source_roofline_is_non_degenerate_without_claiming_pediment_geometry(self) -> None:
        counts = self.report["candidate_source_point_counts"]
        self.assertGreater(counts["WALLSURFACE"], 0)
        self.assertGreater(counts["ROOFSURFACE"], 0)
        self.assertEqual(len(self.report["depth_bands"]), 6)
        self.assertEqual(len(self.report["roofline_profile_31_bins"]), 31)
        self.assertGreater(self.report["profile_active_bin_count"], 3)
        self.assertIsNotNone(self.report["profile_y_min_m"])
        self.assertIsNotNone(self.report["profile_y_max_m"])
        self.assertGreater(self.report["profile_y_max_m"], self.report["profile_y_min_m"])
        self.assertGreater(len(self.report["top_source_vertices"]), 0)

    def test_evidence_lot_stays_unapproved(self) -> None:
        self.assertFalse(self.report["runtime_approved"])
        self.assertFalse(self.report["realism_complete"])
        self.assertEqual(
            self.report["status"],
            "source_roofline_measured_pediment_overlay_not_yet_derived",
        )
        self.assertIn("only if source vertices provide", self.report["next_gate"])


if __name__ == "__main__":
    unittest.main()
