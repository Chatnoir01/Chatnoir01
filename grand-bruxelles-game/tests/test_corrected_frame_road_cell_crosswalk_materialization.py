#!/usr/bin/env python3
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "data/qa/corrected_frame_road_cell_crosswalk_materialization.contract.json"
MIGRATION = ROOT / "data/qa/corrected_frame_road_cell_migration_plan.contract.json"
CURRENT = ROOT / "data/provenance/brussels_road_registered_cell_crosswalk.json"


class CorrectedFrameRoadCellCrosswalkMaterializationTest(unittest.TestCase):
    def test_contract_is_evidence_only_and_exact(self):
        d = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(d["status"], "MEASUREMENT_PENDING")
        self.assertEqual(d["source"]["license"], "ODbL-1.0")
        self.assertEqual(d["source"]["crs"], "EPSG:31370")
        self.assertEqual(d["source"]["migration_plan_semantic_sha256"], "5aff955a11c5b59e610b740ed8b1aca1b55a4eaf32457e01d35f2dfae20fa437")
        self.assertEqual(d["expected"]["candidate_unique_mapped_road_count"], 96)
        self.assertEqual(d["expected"]["candidate_multicell_road_count"], 2)
        self.assertEqual(d["expected"]["candidate_no_registered_overlap_count"], 42)
        self.assertFalse(d["materialization_policy"]["replace_current_crosswalk_authorized"])
        self.assertFalse(d["materialization_policy"]["write_production_crosswalk_authorized"])
        self.assertTrue(all(v is False for v in d["authorization"].values()))

    def test_locked_migration_plan_is_predecessor(self):
        contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
        migration = json.loads(MIGRATION.read_text(encoding="utf-8"))
        self.assertEqual(migration["status"], "LOCKED_MIGRATION_PLAN_EVIDENCE_ONLY")
        self.assertEqual(migration["locked_evidence"]["semantic_sha256"], contract["source"]["migration_plan_semantic_sha256"])
        self.assertEqual(migration["locked_evidence"]["accounting"], contract["expected"])
        self.assertTrue(all(v is False for v in migration["authorization"].values()))

    def test_production_crosswalk_remains_untouched_and_non_authorizing(self):
        current = json.loads(CURRENT.read_text(encoding="utf-8"))
        self.assertEqual(current["mapped_road_count"], 56)
        self.assertFalse(current["road_cell_mapping_authorized"])
        self.assertFalse(current["rendered_geometry_authorized"])
        self.assertFalse(current["collision_authorized"])
        self.assertFalse(current["jouable_promotion_authorized"])


if __name__ == "__main__":
    unittest.main()
