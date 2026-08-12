from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "make_urbis_cell_runtime.py"
SPEC = importlib.util.spec_from_file_location("make_urbis_cell_runtime", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MakeUrbisCellRuntimeTests(unittest.TestCase):
    def test_polygon_area_and_centroid(self) -> None:
        ring = [[100.0, 100.0], [120.0, 100.0], [120.0, 110.0], [100.0, 110.0]]
        self.assertAlmostEqual(MODULE.polygon_area(ring), 200.0)
        self.assertEqual(MODULE.polygon_centroid(ring), (110.0, 105.0))

    def test_half_open_cell_ownership_prevents_double_ownership(self) -> None:
        center = (500.0, 250.0)
        west = (0.0, 0.0, 500.0, 500.0)
        east = (500.0, 0.0, 1000.0, 500.0)
        self.assertFalse(MODULE.owns_centroid(center, west))
        self.assertTrue(MODULE.owns_centroid(center, east))

    def test_runtime_keeps_only_owned_features(self) -> None:
        buildings = {
            "features": [
                {
                    "id": "owned",
                    "properties": {"INSPIRE_ID": "owned"},
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[[100, 100], [120, 100], [120, 120], [100, 120], [100, 100]]],
                    },
                },
                {
                    "id": "east-neighbour",
                    "properties": {"INSPIRE_ID": "east-neighbour"},
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[[510, 100], [530, 100], [530, 120], [510, 120], [510, 100]]],
                    },
                },
            ]
        }
        surfaces = {"features": []}
        runtime = MODULE.build_runtime(buildings, surfaces, (0, 0, 500, 500), "cell-a")
        self.assertEqual(runtime["stats"]["buildings"], 1)
        self.assertEqual(runtime["buildings"][0]["id"], "owned")

    def test_midi_lambert_origin_maps_to_existing_osm_midi_anchor(self) -> None:
        game = MODULE.game_point([MODULE.ORIGIN_E, MODULE.ORIGIN_N])
        self.assertEqual(game, [MODULE.WORLD_ANCHOR_X, MODULE.WORLD_ANCHOR_Z])
        self.assertEqual(game, [-668.5, 627.84])

    def test_east_and_north_axes_match_current_game_convention(self) -> None:
        east = MODULE.game_point([MODULE.ORIGIN_E + 1.0, MODULE.ORIGIN_N])
        north = MODULE.game_point([MODULE.ORIGIN_E, MODULE.ORIGIN_N + 1.0])
        self.assertEqual(east, [-667.5, 627.84])
        self.assertEqual(north, [-668.5, 626.84])


if __name__ == "__main__":
    unittest.main()
