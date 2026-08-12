import json
import math
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data" / "qa" / "photo_match" / "bourse_2019_geotagged_camera_evidence.json"


class BourseGeotaggedCameraEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.data = json.loads(EVIDENCE.read_text(encoding="utf-8"))

    def test_reference_provenance_is_locked(self) -> None:
        ref = self.data["reference"]
        self.assertEqual(self.data["schema"], "grand-bruxelles-bourse-geotagged-camera-evidence-v1")
        self.assertEqual(ref["author"], "Fawaz.tairou")
        self.assertEqual(ref["license"], "CC BY-SA 4.0")
        self.assertEqual(ref["camera_location_wgs84"], [50.848544, 4.349422])
        self.assertAlmostEqual(ref["image_direction_true_degrees"], 135.21993255901, places=9)
        self.assertEqual(ref["focal_length_35mm_equivalent_mm"], 29.0)
        self.assertEqual(ref["source_dimensions_px"], [4032, 3024])

    def test_lambert_to_game_mapping_matches_project_contract(self) -> None:
        transform = self.data["project_transform"]
        e, n = transform["lambert72_camera_e_n_m"]
        origin_e, origin_n = transform["lambert72_origin_e_n_m"]
        world_x, world_z = transform["world_origin_x_z_m"]
        expected_x = world_x + (e - origin_e)
        expected_z = world_z - (n - origin_n)
        game_x, game_z = transform["game_camera_x_z_m"]
        self.assertAlmostEqual(game_x, expected_x, places=9)
        self.assertAlmostEqual(game_z, expected_z, places=9)

    def test_published_heading_agrees_with_authoritative_hero_bearing(self) -> None:
        transform = self.data["project_transform"]
        hero = self.data["hero_witness"]
        camera_x, camera_z = transform["game_camera_x_z_m"]
        hero_x, hero_z = hero["hero_bbox_center_game_x_z_m"]
        east = hero_x - camera_x
        north = -(hero_z - camera_z)
        bearing = math.degrees(math.atan2(east, north)) % 360.0
        distance = math.hypot(east, north)
        heading = self.data["reference"]["image_direction_true_degrees"]
        delta = abs((bearing - heading + 180.0) % 360.0 - 180.0)
        self.assertAlmostEqual(bearing, hero["camera_to_hero_true_bearing_degrees"], places=9)
        self.assertAlmostEqual(distance, hero["camera_to_hero_horizontal_distance_m"], places=9)
        self.assertAlmostEqual(delta, hero["published_heading_delta_degrees"], places=9)
        self.assertLess(delta, 3.0)

    def test_full_frame_equivalent_horizontal_fov_is_reproducible(self) -> None:
        focal = self.data["reference"]["focal_length_35mm_equivalent_mm"]
        expected = math.degrees(2.0 * math.atan(36.0 / (2.0 * focal)))
        self.assertAlmostEqual(
            expected,
            self.data["optics"]["horizontal_fov_from_35mm_equivalent_degrees"],
            places=9,
        )

    def test_candidate_keeps_unproven_height_and_runtime_explicit(self) -> None:
        candidate = self.data["candidate_game_camera_transform"]
        self.assertEqual(candidate["x_z_status"], "source_position_locked")
        self.assertEqual(candidate["yaw_status"], "source_true_heading_locked")
        self.assertEqual(candidate["fov_status"], "source_35mm_equivalent_derived")
        self.assertEqual(candidate["y_status"], "provisional_eye_height_not_source_altitude")
        self.assertFalse(self.data["runtime_approved"])
        self.assertFalse(self.data["realism_complete"])


if __name__ == "__main__":
    unittest.main()
