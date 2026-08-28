#!/usr/bin/env python3
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "data/qa/corrected_frame_road_cell_crosswalk_materialization.contract.json"
MIGRATION = ROOT / "data/qa/corrected_frame_road_cell_migration_plan.contract.json"
CURRENT = ROOT / "data/provenance/brussels_road_registered_cell_crosswalk.json"
WORKFLOW = ROOT.parent / ".github/workflows/grand-bruxelles-corrected-frame-road-cell-crosswalk-materialization.yml"


class CorrectedFrameRoadCellCrosswalkMaterializationTest(unittest.TestCase):
    def test_contract_is_locked_evidence_only_and_exact(self):
        d = json.loads(CONTRACT.read_text(encoding="utf-8"))
        self.assertEqual(d["status"], "LOCKED_CANDIDATE_EVIDENCE_ONLY")
        self.assertEqual(d["source"]["license"], "ODbL-1.0")
        self.assertEqual(d["source"]["crs"], "EPSG:31370")
        self.assertEqual(d["source"]["migration_plan_semantic_sha256"], "5aff955a11c5b59e610b740ed8b1aca1b55a4eaf32457e01d35f2dfae20fa437")
        self.assertEqual(d["expected"]["candidate_unique_mapped_road_count"], 96)
        self.assertEqual(d["expected"]["candidate_multicell_road_count"], 2)
        self.assertEqual(d["expected"]["candidate_no_registered_overlap_count"], 42)
        locked = d["locked_evidence"]
        self.assertEqual(locked["workflow_run_id"], 33062220654)
        self.assertEqual(locked["artifact_id"], 9642195509)
        self.assertEqual(locked["artifact_sha256"], "a9f5d7f129f5c48b02094bb35d1b06643bcb133e54411483f471268308a1bd63")
        self.assertEqual(locked["candidate_json_sha256"], "3a3b9f3d5be97cec930a39a69a627d4638d5b4672e31c607efee07c0c978e640")
        self.assertEqual(locked["semantic_sha256"], "9fca92b20a3a45b8d9d8c8740a3e355cf993d9961797ed5a8e1a13f14989b173")
        self.assertEqual(locked["candidate_unique_mapped_road_count"], 96)
        self.assertEqual(locked["candidate_multicell_road_count"], 2)
        self.assertEqual(locked["candidate_no_registered_overlap_count"], 42)
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

    def test_historical_migration_receipt_is_replayed_at_its_evidence_base(self):
        contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
        migration = json.loads(MIGRATION.read_text(encoding="utf-8"))
        self.assertNotEqual(migration["production_base_sha"], contract["production_base_sha"])
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("IMPACT_BASE_SHA MIGRATION_BASE_SHA MATERIALIZATION_EVIDENCE_BASE_SHA MIGRATION_SEMANTIC", workflow)
        self.assertIn('for sha in "$IMPACT_BASE_SHA" "$MIGRATION_BASE_SHA" "$MATERIALIZATION_EVIDENCE_BASE_SHA"; do', workflow)
        self.assertIn('git cat-file -e "${sha}^{commit}"', workflow)
        self.assertIn('git merge-base --is-ancestor "$sha" "$LIVE_MAIN_SHA"', workflow)
        self.assertIn("--production-base-sha \"$MIGRATION_BASE_SHA\"", workflow)
        self.assertNotIn("--production-base-sha \"$LIVE_MAIN_SHA\"\n          --output \"$RUNNER_TEMP/corrected-frame-road-cell-migration-plan.json\"", workflow)

    def test_historical_impact_replay_uses_its_56_row_crosswalk(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("IMPACT_HISTORICAL_CROSSWALK", workflow)
        self.assertIn("MIGRATION_HISTORICAL_CROSSWALK", workflow)
        self.assertIn("MATERIALIZATION_HISTORICAL_CROSSWALK", workflow)
        self.assertIn("git show \"$IMPACT_BASE_SHA:grand-bruxelles-game/data/provenance/brussels_road_registered_cell_crosswalk.json\"", workflow)
        self.assertIn("--current-crosswalk \"$IMPACT_HISTORICAL_CROSSWALK\"", workflow)
        self.assertIn("--current-crosswalk \"$MIGRATION_HISTORICAL_CROSSWALK\"", workflow)
        self.assertIn("--current-crosswalk \"$MATERIALIZATION_HISTORICAL_CROSSWALK\"", workflow)
        self.assertIn("d['mapped_road_count']==56", workflow)
        self.assertIn("len(d['rows'])==56", workflow)

    def test_lock_reproduction_checks_candidate_json_hash(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("candidate_json_sha256", workflow)
        self.assertIn("hashlib.sha256", workflow)

    def test_branch_crosswalk_is_corrected_frame_pair_but_still_non_authorizing(self):
        current = json.loads(CURRENT.read_text(encoding="utf-8"))
        self.assertEqual(current["mapped_road_count"], 96)
        self.assertEqual(current["mapped_cell_count"], 4)
        self.assertEqual(len(current["rows"]), 96)
        self.assertEqual(current["destination_readiness"], "CORRECTED_FRAME_ROAD_CELL_CROSSWALK_EVIDENCE_ONLY")
        hold_ids = {256158619, 397461693}
        self.assertFalse(hold_ids & {int(row["road_osm_id"]) for row in current["rows"]})
        self.assertFalse(current["road_cell_mapping_authorized"])
        self.assertFalse(current["runtime_mount_authorized"])
        self.assertFalse(current["rendered_geometry_authorized"])
        self.assertFalse(current["collision_authorized"])
        self.assertFalse(current["safe_spawn_authorized"])
        self.assertFalse(current["jouable_promotion_authorized"])


if __name__ == "__main__":
    unittest.main()
