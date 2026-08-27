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

    def test_semantic_identity_ignores_only_live_main_continuity(self):
        common = {
            "schema": "measurement-v2",
            "status": "MEASURED_FRAME_CORRECTION_IMPACT_EVIDENCE_ONLY",
            "source_sha256": "source",
            "candidate_frame": {"origin_easting_m": 1.0, "origin_northing_m": 2.0},
            "accounting": {"candidate_unique_mapped_road_count": 96},
            "authorization": {"road_cell_mapping_authorized": False},
        }
        a = dict(common, production_base_sha="main-a")
        b = dict(common, production_base_sha="main-b")
        self.assertEqual(
            impact.canonical_sha256(impact.semantic_identity_basis(a)),
            impact.canonical_sha256(impact.semantic_identity_basis(b)),
        )
        changed = dict(b)
        changed["accounting"] = {"candidate_unique_mapped_road_count": 95}
        self.assertNotEqual(
            impact.canonical_sha256(impact.semantic_identity_basis(a)),
            impact.canonical_sha256(impact.semantic_identity_basis(changed)),
        )

    def test_locked_artifact_reduces_to_stable_semantic(self):
        artifact = {
            "schema": "grand-bruxelles-osm-road-frame-correction-impact-measurement-v1",
            "status": "MEASURED_FRAME_CORRECTION_IMPACT_EVIDENCE_ONLY",
            "production_base_sha": "032bae0e3f374739f12909e9706f51bcf3c826a8",
            "source_sha256": "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398",
        }
        # This test guards the policy mechanically; the authoritative full-artifact
        # reduction is pinned in the contract as stable_semantic_sha256.
        self.assertNotIn("production_base_sha", impact.semantic_identity_basis(artifact))

    def test_contract_keeps_every_authorization_closed_and_evidence_locked(self):
        contract = json.loads((ROOT / "data" / "qa" / "osm_road_frame_correction_impact.contract.json").read_text())
        self.assertEqual(contract["schema"], "grand-bruxelles-osm-road-frame-correction-impact-v2")
        self.assertEqual(contract["status"], "LOCKED_IMPACT_MEASUREMENT_EVIDENCE_ONLY")
        self.assertEqual(contract["source"]["license"], "ODbL-1.0")
        self.assertEqual(contract["frame_review"]["crs"], "EPSG:31370")
        self.assertTrue(all(value is False for value in contract["authorization"].values()))
        self.assertFalse(contract["measurement_policy"]["mutate_source"])
        self.assertFalse(contract["measurement_policy"]["mutate_registered_index"])
        self.assertFalse(contract["measurement_policy"]["mutate_current_crosswalk"])
        self.assertEqual(contract["semantic_identity_policy"]["exclude_continuity_fields"], ["production_base_sha"])
        locked = contract["locked_evidence"]
        self.assertEqual(locked["artifact_id"], 9630512617)
        self.assertEqual(locked["artifact_semantic_sha256"], "cd24d32e811b57a672988dd0644e932434d1c36e9021eb944d6f8c79b16369fd")
        self.assertEqual(locked["stable_semantic_sha256"], "2941ea86fd0e2ad524f6f788349aa9745e16809c3343a3fa063eb4b23494ac62")
        self.assertEqual(locked["accounting"]["candidate_unique_mapped_road_count"], 96)
        self.assertEqual(locked["accounting"]["retained_mapping_count"], 0)
        self.assertEqual(locked["accounting"]["changed_mapping_count"], 45)


if __name__ == "__main__":
    unittest.main()
