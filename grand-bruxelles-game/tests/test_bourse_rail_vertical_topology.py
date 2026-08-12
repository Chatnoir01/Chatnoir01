from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TRANSFORM_PATH = ROOT / "tools" / "transform_osm_to_game.py"
RUNTIME_OSM = ROOT / "data" / "osm" / "vertical_slice_01.game.json"
MASK_SCRIPT = ROOT / "game" / "scripts" / "bourse_rail_vertical_mask.gd"
MAIN_SCENE = ROOT / "game" / "main.tscn"
BOURSE = (81.54, -664.58)
RADIUS_M = 120.0

spec = importlib.util.spec_from_file_location("transform_osm_to_game", TRANSFORM_PATH)
transform = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(transform)


def point_segment_distance(point, start, finish) -> float:
    px, pz = point
    ax, az = start
    bx, bz = finish
    dx = bx - ax
    dz = bz - az
    length_sq = dx * dx + dz * dz
    if length_sq <= 1e-12:
        return math.hypot(px - ax, pz - az)
    amount = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / length_sq))
    qx = ax + dx * amount
    qz = az + dz * amount
    return math.hypot(px - qx, pz - qz)


class BourseRailVerticalTopologyRegression(unittest.TestCase):
    def test_converter_preserves_explicit_vertical_topology(self) -> None:
        def way(osm_id: int, tags: dict) -> dict:
            return {
                "type": "way",
                "id": osm_id,
                "tags": {"railway": "tram", **tags},
                "geometry": [
                    {"lat": 50.8419, "lon": 4.3480},
                    {"lat": 50.8420, "lon": 4.3481},
                ],
            }

        converted = transform.convert(
            {
                "elements": [
                    way(1, {"tunnel": "yes", "layer": "-1"}),
                    way(2, {"covered": "yes"}),
                    way(3, {"layer": "-2"}),
                    way(4, {}),
                ]
            },
            transform.DEFAULT_ORIGIN,
        )
        rails = {rail["osm_id"]: rail for rail in converted["railways"]}

        self.assertTrue(rails[1]["tunnel"])
        self.assertEqual(rails[1]["layer"], -1.0)
        self.assertFalse(rails[1]["surface_visible"])
        self.assertTrue(rails[2]["covered"])
        self.assertFalse(rails[2]["surface_visible"])
        self.assertEqual(rails[3]["layer"], -2.0)
        self.assertFalse(rails[3]["surface_visible"])
        self.assertFalse(rails[4]["tunnel"])
        self.assertFalse(rails[4]["covered"])
        self.assertEqual(rails[4]["layer"], 0.0)
        self.assertTrue(rails[4]["surface_visible"])

    def test_current_legacy_runtime_has_unresolved_rail_geometry_at_bourse(self) -> None:
        data = json.loads(RUNTIME_OSM.read_text(encoding="utf-8"))
        self.assertEqual(data["format"], "grand-bruxelles-osm-v1")
        railways = data["railways"]
        self.assertGreater(len(railways), 0)
        self.assertTrue(
            all(
                "surface_visible" not in railway
                and "tunnel" not in railway
                and "covered" not in railway
                and "layer" not in railway
                for railway in railways
            )
        )

        affected_segments = 0
        minimum_distance = float("inf")
        for railway in railways:
            points = railway.get("points", [])
            for index in range(len(points) - 1):
                distance = point_segment_distance(BOURSE, points[index], points[index + 1])
                minimum_distance = min(minimum_distance, distance)
                if distance <= RADIUS_M:
                    affected_segments += 1

        self.assertLess(minimum_distance, RADIUS_M)
        self.assertGreater(affected_segments, 0)

    def test_runtime_mask_is_registered_and_bourse_scoped(self) -> None:
        mask = MASK_SCRIPT.read_text(encoding="utf-8")
        scene = MAIN_SCENE.read_text(encoding="utf-8")
        self.assertIn("const BOURSE_ANCHOR := Vector2(81.54, -664.58)", mask)
        self.assertIn("uncertainty_radius_m: float = 120.0", mask)
        self.assertIn("_legacy_runtime_lacks_vertical_topology", mask)
        self.assertIn('"../BrusselsOSM/GeneratedRails"', mask)
        self.assertIn("point.distance_to(BOURSE_ANCHOR) > uncertainty_radius_m", mask)
        self.assertIn("res://game/scripts/bourse_rail_vertical_mask.gd", scene)
        self.assertIn('[node name="BourseRailVerticalMask" type="Node" parent="."]', scene)


if __name__ == "__main__":
    unittest.main()
