#!/usr/bin/env python3
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "data/qa/corrected_frame_road_cell_migration_plan.contract.json"
TOOL = ROOT / "tools/qa/measure_corrected_frame_road_cell_migration_plan.py"
CANDIDATE = ROOT / "data/qa/corrected_frame_road_cell_crosswalk_candidate.contract.json"
CURRENT = ROOT / "data/provenance/brussels_road_registered_cell_crosswalk.json"


class CorrectedFrameRoadCellMigrationPlanTest(unittest.TestCase):
    def test_contract_preserves_evidence_only_boundary(self):
        d = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(d["status"], "LOCKED_MIGRATION_PLAN_EVIDENCE_ONLY")
        self.assertEqual(d["source"]["license"], "ODbL-1.0")
        self.assertEqual(d["source"]["crs"], "EPSG:31370")
        self.assertEqual(d["expected"]["current_mapped_road_count"], 56)
        self.assertEqual(d["expected"]["candidate_unique_mapped_road_count"], 96)
        self.assertEqual(d["expected"]["retained_mapping_count"], 0)
        self.assertEqual(d["expected"]["changed_mapping_count"], 45)
        self.assertEqual(d["expected"]["newly_mappable_count"], 51)
        self.assertEqual(d["expected"]["no_longer_mappable_count"], 11)
        self.assertEqual(d["locked_evidence"]["semantic_sha256"], "5aff955a11c5b59e610b740ed8b1aca1b55a4eaf32457e01d35f2dfae20fa437")
        self.assertEqual(d["locked_evidence"]["accounting"], d["expected"])
        self.assertTrue(d["migration_policy"]["atomic_rebuild_required"])
        self.assertFalse(d["migration_policy"]["replace_current_crosswalk_authorized"])
        self.assertFalse(d["migration_policy"]["carry_old_mapping_without_reproof_authorized"])
        self.assertFalse(d["migration_policy"]["multicell_mapping_authorized"])
        self.assertTrue(all(value is False for value in d["authorization"].values()))

    def test_candidate_and_current_crosswalk_remain_non_authorizing(self):
        candidate = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        current = json.loads(CURRENT.read_text(encoding="utf-8"))
        self.assertEqual(candidate["semantic_sha256"], "7d8a943297a16cc855e67128b979f3e538193706087df419c9709b1751b53dc1")
        self.assertFalse(candidate["promotion_policy"]["replace_current_crosswalk_authorized"])
        self.assertTrue(all(value is False for value in candidate["authorization"].values()))
        self.assertEqual(current["mapped_road_count"], 56)
        self.assertFalse(current["road_cell_mapping_authorized"])
        self.assertFalse(current["rendered_geometry_authorized"])
        self.assertFalse(current["collision_authorized"])
        self.assertFalse(current["jouable_promotion_authorized"])

    def test_measurement_engine_guards_multicell_and_semantic_identity(self):
        text = TOOL.read_text(encoding="utf-8")
        self.assertIn('assert not (set(candidate_by_id) & hold_ids)', text)
        self.assertIn('assert accounting == contract["expected"]', text)
        self.assertIn('basis.pop("production_base_sha")', text)
        self.assertIn('LOCKED_MIGRATION_PLAN_EVIDENCE_ONLY', text)
        self.assertIn('locked["semantic_sha256"] == output["semantic_sha256"]', text)
        self.assertNotIn('road_cell_mapping_authorized": true', text)
        self.assertNotIn('jouable_promotion_authorized": true', text)


if __name__ == "__main__":
    unittest.main()
