from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SELECTOR_PATH = ROOT / "tools" / "select_bourse_geotagged_context.py"
CAMERA_PATH = ROOT / "data" / "qa" / "photo_match" / "bourse_2019_geotagged_camera_evidence.json"
OLD_FRONTAGE_EVIDENCE = ROOT / "data" / "qa" / "bourse_frontage_lod2_evidence.json"

spec = importlib.util.spec_from_file_location("select_bourse_geotagged_context", SELECTOR_PATH)
selector = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(selector)


class BourseGeotaggedContextSelectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.camera = json.loads(CAMERA_PATH.read_text(encoding="utf-8"))

    def test_synthetic_selection_keeps_only_geometry_inside_view_cone(self) -> None:
        transform = self.camera["project_transform"]
        ref = self.camera["reference"]
        optics = self.camera["optics"]
        camera_e, camera_n = transform["lambert72_camera_e_n_m"]
        heading = ref["image_direction_true_degrees"]
        distance = 80.0

        def point_for_bearing(bearing_degrees: float) -> list[float]:
            radians = math.radians(bearing_degrees)
            return [
                camera_e + math.sin(radians) * distance,
                camera_n + math.cos(radians) * distance,
            ]

        def feature(identifier: str, bearing: float) -> dict:
            center = point_for_bearing(bearing)
            e, n = center
            return {
                "type": "Feature",
                "id": f"building.{identifier}",
                "properties": {"INSPIRE_ID": f"https://databrussels.be/id/building/{identifier}"},
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [e - 2.0, n - 2.0],
                        [e + 2.0, n - 2.0],
                        [e + 2.0, n + 2.0],
                        [e - 2.0, n + 2.0],
                        [e - 2.0, n - 2.0],
                    ]],
                },
            }

        buildings = {
            "type": "FeatureCollection",
            "features": [
                feature("inside", heading),
                feature("edge", heading + optics["horizontal_fov_from_35mm_equivalent_degrees"] * 0.45),
                feature("outside", heading + 90.0),
            ],
        }
        selected = selector.select_candidates(
            buildings,
            camera_e,
            camera_n,
            heading,
            optics["horizontal_fov_from_35mm_equivalent_degrees"],
            180.0,
            3.0,
            12,
        )
        ids = {row["building_id"] for row in selected}
        self.assertIn("https://databrussels.be/id/building/inside", ids)
        self.assertIn("https://databrussels.be/id/building/edge", ids)
        self.assertNotIn("https://databrussels.be/id/building/outside", ids)

    def test_old_rejected_frontage_pair_is_outside_new_source_camera(self) -> None:
        old = json.loads(OLD_FRONTAGE_EVIDENCE.read_text(encoding="utf-8"))
        by_id = {row["building_id"].rsplit("/", 1)[-1]: row for row in old["candidates"]}
        camera_e, camera_n = self.camera["project_transform"]["lambert72_camera_e_n_m"]
        heading = self.camera["reference"]["image_direction_true_degrees"]
        half_fov = self.camera["optics"]["horizontal_fov_from_35mm_equivalent_degrees"] * 0.5

        for short_id in ("1638842", "1643317"):
            west, south, east, north = by_id[short_id]["bbox"]
            points = [
                (west, south), (west, north), (east, south), (east, north),
                ((west + east) * 0.5, (south + north) * 0.5),
            ]
            minimum_delta = min(
                selector.normalize_delta_degrees(
                    selector.true_bearing_degrees(camera_e, camera_n, e, n) - heading
                )
                for e, n in points
            )
            self.assertGreater(minimum_delta, half_fov + 3.0)

    def test_hero_is_never_returned_as_context(self) -> None:
        camera_e, camera_n = self.camera["project_transform"]["lambert72_camera_e_n_m"]
        heading = self.camera["reference"]["image_direction_true_degrees"]
        radians = math.radians(heading)
        e = camera_e + math.sin(radians) * 90.0
        n = camera_n + math.cos(radians) * 90.0
        buildings = {
            "type": "FeatureCollection",
            "features": [{
                "type": "Feature",
                "id": "building.hero",
                "properties": {"INSPIRE_ID": selector.HERO_BUILDING_ID},
                "geometry": {"type": "Point", "coordinates": [e, n]},
            }],
        }
        selected = selector.select_candidates(buildings, camera_e, camera_n, heading, 63.0, 180.0, 3.0, 12)
        self.assertEqual(selected, [])


if __name__ == "__main__":
    unittest.main()
