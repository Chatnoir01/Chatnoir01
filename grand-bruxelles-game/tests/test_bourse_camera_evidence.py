import json
import math
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data" / "qa" / "photo_match" / "bourse_camera_evidence.json"
CAPTURE = ROOT / "game" / "tests" / "photo_match_capture_test.gd"


class BourseCameraEvidenceRegression(unittest.TestCase):
    def test_camera_is_reproducibly_bounded_by_official_geometry(self) -> None:
        data = json.loads(EVIDENCE.read_text(encoding="utf-8"))
        self.assertEqual(data["schema"], "grand-bruxelles-bourse-camera-evidence-v1")
        self.assertEqual(data["reference"]["license"], "CC0-1.0")
        self.assertEqual(data["reference"]["image_size_px"], [4032, 3024])
        self.assertEqual(data["reference"]["focal_length_35mm_equivalent_mm"], 26)
        self.assertFalse(data["runtime_approved"])
        self.assertFalse(data["realism_complete"])

        hero = data["official_hero"]
        min_e, min_n, max_e, max_n = hero["source_bbox_xy"]
        origin_e, origin_n = hero["lambert72_origin"]
        world_x, world_z = hero["world_origin_xz"]
        west_x = world_x + (min_e - origin_e)
        z_min = world_z - (min_n - origin_n)
        z_max = world_z - (max_n - origin_n)
        center_z = (z_min + z_max) * 0.5
        span = abs(z_min - z_max)
        self.assertAlmostEqual(west_x, hero["derived_world_west_face_x"], places=9)
        self.assertAlmostEqual(center_z, hero["derived_world_frontage_center_z"], places=9)
        self.assertAlmostEqual(span, hero["derived_world_frontage_span_m"], places=9)

        policy = data["candidate_policy"]
        transform = policy["camera_transform"]
        fraction = policy["horizontal_bbox_occupancy_fraction"]
        fov = math.radians(transform["fov_degrees"] * fraction)
        expected_standoff = (span * 0.5) / math.tan(fov * 0.5)
        self.assertAlmostEqual(expected_standoff, policy["standoff_m"], places=9)
        self.assertAlmostEqual(transform["position"][0], west_x - expected_standoff, places=9)
        self.assertAlmostEqual(transform["position"][2], center_z, places=9)
        self.assertEqual(transform["status"], "provisional_evidence_bounded")

        eye_y = transform["position"][1]
        bottom_angle = math.degrees(math.atan2(-eye_y, expected_standoff))
        top_angle = math.degrees(math.atan2(hero["height_m"] - eye_y, expected_standoff))
        expected_pitch = -(bottom_angle + top_angle) * 0.5
        self.assertAlmostEqual(transform["rotation_degrees"][0], expected_pitch, places=9)
        self.assertEqual(transform["rotation_degrees"][1:], [-90.0, 0.0])

    def test_capture_consumes_bounded_evidence_not_old_manifest_pose(self) -> None:
        text = CAPTURE.read_text(encoding="utf-8")
        self.assertIn('CAMERA_EVIDENCE_PATH := "res://data/qa/photo_match/bourse_camera_evidence.json"', text)
        self.assertIn('candidate_policy.get("camera_transform", {})', text)
        self.assertIn('runtime_approved', text)
        self.assertNotIn('viewpoint.get("game_camera_transform", {})', text)


if __name__ == "__main__":
    unittest.main()
