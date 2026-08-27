import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "qa" / "measure_osm_road_frame_correction_impact.py"
spec = importlib.util.spec_from_file_location("impact", TOOL)
impact = importlib.util.module_from_spec(spec)
spec.loader.exec_module(impact)


class TestRoadFrameCorrectionImpact(unittest.TestCase):
    def test_segment_rectangle_intersection_exact(self):
        box = [10.0, 20.0, 20.0, 30.0]
        self.assertTrue(impact.segment_intersects_rect([0, 25], [30, 25], box))
        self.assertTrue(impact.segment_intersects_rect([0, 10], [10, 20], box))  # corner contact
        self.assertTrue(impact.segment_intersects_rect([10, 20], [20, 30], box))
        self.assertFalse(impact.segment_intersects_rect([0, 19], [30, 19], box))
        self.assertFalse(impact.segment_intersects_rect([0, 0], [9, 19], box))

    def test_candidate_frame_transform(self):
        p = impact.local_to_lambert([319.01, -535.2], 148538.362136, 170165.796688)
        self.assertAlmostEqual(p[0], 148857.372136, places=6)
        self.assertAlmostEqual(p[1], 170700.996688, places=6)

    def test_contract_keeps_every_authorization_closed_and_evidence_locked(self):
        contract = json.loads((ROOT / "data" / "qa" / "osm_road_frame_correction_impact.contract.json").read_text())
        self.assertEqual(contract["status"], "LOCKED_IMPACT_MEASUREMENT_EVIDENCE_ONLY")
        self.assertEqual(contract["source"]["license"], "ODbL-1.0")
        self.assertEqual(contract["frame_review"]["crs"], "EPSG:31370")
        self.assertTrue(all(value is False for value in contract["authorization"].values()))
        self.assertFalse(contract["measurement_policy"]["mutate_source"])
        self.assertFalse(contract["measurement_policy"]["mutate_registered_index"])
        self.assertFalse(contract["measurement_policy"]["mutate_current_crosswalk"])
        locked = contract["locked_evidence"]
        self.assertEqual(locked["artifact_id"], 9630512617)
        self.assertEqual(locked["semantic_sha256"], "cd24d32e811b57a672988dd0644e932434d1c36e9021eb944d6f8c79b16369fd")
        self.assertEqual(locked["accounting"]["candidate_unique_mapped_road_count"], 96)
        self.assertEqual(locked["accounting"]["retained_mapping_count"], 0)
        self.assertEqual(locked["accounting"]["changed_mapping_count"], 45)


if __name__ == "__main__":
    unittest.main()
