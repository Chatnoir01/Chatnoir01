from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HERO = ROOT / "data" / "urbis" / "heroes" / "bourse_lod2.game.json"
ANALYZER = ROOT / "tools" / "analyze_bourse_vertical_anchor.py"

spec = importlib.util.spec_from_file_location("analyze_bourse_vertical_anchor", ANALYZER)
analyzer = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(analyzer)


class BourseVerticalAnchorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.hero = json.loads(HERO.read_text(encoding="utf-8"))
        cls.report = analyzer.summarize(cls.hero)

    def test_source_base_matches_authoritative_minimum(self) -> None:
        self.assertAlmostEqual(
            self.report["source_base_z_m"],
            self.report["source_z_min_m"],
            places=6,
        )
        self.assertAlmostEqual(self.report["game_y_min_m"], 0.0, places=6)
        self.assertAlmostEqual(
            self.report["game_height_m"],
            self.report["source_height_m"],
            places=4,
        )

    def test_ground_surface_is_actually_at_game_ground(self) -> None:
        ground = self.report["ground_anchor"]
        self.assertTrue(ground["present"])
        self.assertIsNotNone(ground["y_min_m"])
        self.assertLessEqual(ground["y_min_m"], 0.05)
        # UrbIS ground may slope, but the semantic ground face must not float metres above base.
        self.assertLess(ground["y_max_m"], 2.0)

    def test_authoritative_walls_reach_the_building_base(self) -> None:
        wall = self.report["wall_base"]
        self.assertTrue(wall["present"])
        self.assertIsNotNone(wall["y_min_m"])
        self.assertLessEqual(wall["y_min_m"], 0.10)
        self.assertGreater(wall["triangles_touching_0_50m"], 0)
        self.assertGreater(wall["triangles_touching_1_00m"], 0)

    def test_roof_is_above_ground_and_runtime_claims_remain_open(self) -> None:
        roof = self.report["roof"]
        self.assertTrue(roof["present"])
        self.assertGreater(roof["y_min_m"], 2.0)
        self.assertFalse(self.report["runtime_approved"])
        self.assertFalse(self.report["realism_complete"])


if __name__ == "__main__":
    unittest.main()
