#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/qa/measure_grand_place_corrected_road_frame_cell.py"
spec = importlib.util.spec_from_file_location("gp_corrected_frame", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


class GrandPlaceCorrectedRoadFrameCellTest(unittest.TestCase):
    def test_grid_identity_is_global_500m(self) -> None:
        self.assertEqual(mod.grid_id((148852.74417614136, 170704.8857889818)), "E148500_N170500")
        self.assertEqual(mod.grid_id((148187.30422791935, 170073.82414926199)), "E148000_N170000")

    def test_corrected_anchor_is_close_to_official(self) -> None:
        corrected = mod.project_local((148538.362136, 170165.796688), [319.01, -535.2])
        official = (148852.74417614136, 170704.8857889818)
        self.assertEqual(mod.grid_id(corrected), "E148500_N170500")
        self.assertLess(__import__("math").dist(corrected, official), 10.0)

    def test_amigo_hits_target_only_under_corrected_candidate(self) -> None:
        road = {
            "osm_id": 13842686,
            "points": [[220.618,-531.539],[222.811,-524.448],[222.987,-523.892],[239.323,-498.355],[251.843,-476.614],[257.522,-467.386]],
        }
        bbox = [148500.0, 170500.0, 149000.0, 171000.0]
        old = mod.road_target_hits(road, (147868.29422791934, 169538.62414926197), bbox)
        new = mod.road_target_hits(road, (148538.362136, 170165.796688), bbox)
        self.assertEqual((old["point_hits"], old["segment_hits"]), (0, 0))
        self.assertEqual((new["point_hits"], new["segment_hits"]), (6, 5))

    def test_charbon_hits_target_only_under_corrected_candidate(self) -> None:
        road = {"osm_id": 684214770, "points": [[144.721,-492.121],[164.72,-502.107],[220.618,-531.539]]}
        bbox = [148500.0, 170500.0, 149000.0, 171000.0]
        old = mod.road_target_hits(road, (147868.29422791934, 169538.62414926197), bbox)
        new = mod.road_target_hits(road, (148538.362136, 170165.796688), bbox)
        self.assertEqual((old["point_hits"], old["segment_hits"]), (0, 0))
        self.assertEqual((new["point_hits"], new["segment_hits"]), (3, 2))

    def test_authorization_stays_closed(self) -> None:
        self.assertTrue(mod.CLOSED_AUTH)
        self.assertTrue(all(v is False for v in mod.CLOSED_AUTH.values()))
        self.assertIn("shared_frame_change_authorized", mod.CLOSED_AUTH)
        self.assertIn("jouable_promotion_authorized", mod.CLOSED_AUTH)


if __name__ == "__main__":
    unittest.main()
