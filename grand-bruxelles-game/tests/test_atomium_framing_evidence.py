from __future__ import annotations

import json
import math
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PROJECT_ROOT / "data" / "qa" / "photo_match" / "manifest.json"
EVIDENCE_PATH = PROJECT_ROOT / "data" / "qa" / "photo_match" / "atomium_ground_framing_evidence.json"


class AtomiumFramingEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        self.evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
        self.atomium = next(
            ref for ref in self.manifest["references"] if ref["id"] == "atomium_ground_oblique_v1"
        )

    def test_global_registry_uses_evidence_bounded_candidate(self) -> None:
        transform = self.atomium["viewpoint"]["game_camera_transform"]
        bound = self.evidence["framing_bound"]
        self.assertEqual(transform["status"], "provisional")
        self.assertAlmostEqual(transform["fov_degrees"], 31.5, places=6)
        self.assertAlmostEqual(transform["fov_degrees"], bound["benchmark_fov_degrees"], places=6)
        self.assertLessEqual(transform["fov_degrees"], bound["maximum_fov_consistent_with_witness_deg"])
        self.assertFalse(self.atomium["realism_complete"])
        self.assertIsNone(self.atomium["viewpoint"]["game_screenshot"])

    def test_coordinate_contract_preserves_epsg31370_scale(self) -> None:
        contract = self.evidence["coordinate_contract"]
        self.assertEqual(contract["crs"], "EPSG:31370")
        self.assertEqual(contract["axes"], "X=east, Y=up, Z=south")
        camera = contract["camera_epsg31370"]
        target = contract["atomium_epsg31370"]
        distance = math.hypot(target[0] - camera[0], target[1] - camera[1])
        self.assertAlmostEqual(distance, contract["camera_to_target_horizontal_distance_m"], places=3)
        self.assertAlmostEqual(contract["subject_official_height_m"], 102.0, places=6)

    def test_specialist_capture_is_evidence_not_current_main_capture(self) -> None:
        capture = self.evidence["capture_evidence"]
        self.assertIn("not a current-main runtime capture", capture["scope"])
        self.assertEqual(capture["render_resolution_px"], [1280, 720])
        self.assertEqual(len(capture["artifact_sha256"]), 64)
        blockers = self.evidence["reality_status"]["remaining_blockers"]
        self.assertTrue(any("Current-main deterministic Atomium runtime capture" in item for item in blockers))
        self.assertFalse(self.evidence["reality_status"]["realism_complete"])


if __name__ == "__main__":
    unittest.main()
