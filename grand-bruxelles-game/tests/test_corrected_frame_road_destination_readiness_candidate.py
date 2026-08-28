import importlib.util
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "qa" / "materialize_corrected_frame_road_destination_readiness_candidate.py"
WORKFLOW_PATH = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-corrected-frame-road-destination-readiness-candidate.yml"
TOOLS_QA = str(MODULE_PATH.parent)
if TOOLS_QA not in sys.path:
    sys.path.insert(0, TOOLS_QA)
spec = importlib.util.spec_from_file_location("corrected_readiness", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)


class CorrectedFrameReadinessCandidateTest(unittest.TestCase):
    def candidate(self):
        return {
            "schema": "grand-bruxelles-corrected-frame-road-cell-crosswalk-materialization-candidate-v1",
            "status": "CANDIDATE_EVIDENCE_ONLY_NOT_APPLIED",
            "semantic_sha256": "a" * 64,
            "rows": [
                {"road_osm_id": 8176386, "cell_id": "bxl-e147500-n169500-s500"},
                {"road_osm_id": 150205016, "cell_id": "bxl-e147500-n170000-s500"},
                {"road_osm_id": 13767417, "cell_id": "bxl-e148000-n170000-s500"},
                {"road_osm_id": 8512036, "cell_id": "bxl-e148500-n170500-s500"},
            ],
            "multicell_hold_rows": [],
            "materialization_policy": {
                "replace_current_crosswalk_authorized": False,
                "write_production_crosswalk_authorized": False,
            },
            "authorization": {
                "production_frame_update_authorized": False,
                "road_cell_mapping_authorized": False,
                "runtime_mount_authorized": False,
                "rendered_geometry_authorized": False,
                "collision_authorized": False,
                "safe_spawn_authorized": False,
                "jouable_promotion_authorized": False,
            },
        }

    def test_grid_cell_identity(self):
        self.assertEqual(mod.grid_cell_id("bxl-e148500-n170500-s500"), "E148500_N170500")
        with self.assertRaises(RuntimeError):
            mod.grid_cell_id("E148500_N170500")

    def test_candidate_crosswalk_is_evidence_only_and_order_stable(self):
        out = mod.build_candidate_crosswalk(self.candidate(), "b" * 64)
        self.assertEqual(out["mapped_road_count"], 4)
        self.assertEqual(out["mapped_cell_count"], 4)
        self.assertEqual([row["road_osm_id"] for row in out["rows"]], sorted([8176386, 150205016, 13767417, 8512036]))
        self.assertTrue(all(row["mapping_evidence_only"] is True for row in out["rows"]))
        self.assertTrue(all(row["road_cell_mapping_authorized"] is False for row in out["rows"]))
        self.assertTrue(all(value is False for key, value in out.items() if key.endswith("_authorized")))

    def test_duplicate_road_id_fails_closed(self):
        candidate = self.candidate()
        candidate["rows"].append(dict(candidate["rows"][0]))
        with self.assertRaises(RuntimeError):
            mod.build_candidate_crosswalk(candidate, "b" * 64)

    def test_multicell_hold_cannot_leak_into_unique_mapping(self):
        candidate = self.candidate()
        candidate["multicell_hold_rows"] = [
            {"road_osm_id": candidate["rows"][0]["road_osm_id"], "candidate_cell_ids": ["bxl-e147500-n169500-s500", "bxl-e147500-n170000-s500"]}
        ]
        with self.assertRaises(RuntimeError):
            mod.build_candidate_crosswalk(candidate, "b" * 64)

    def test_duplicate_multicell_hold_id_fails_closed(self):
        candidate = self.candidate()
        hold = {"road_osm_id": 256158619, "candidate_cell_ids": ["bxl-e147500-n169500-s500", "bxl-e147500-n170000-s500"]}
        candidate["multicell_hold_rows"] = [hold, dict(hold)]
        with self.assertRaises(RuntimeError):
            mod.build_candidate_crosswalk(candidate, "b" * 64)

    def test_open_authorization_fails_closed(self):
        candidate = self.candidate()
        candidate["authorization"]["road_cell_mapping_authorized"] = True
        with self.assertRaises(RuntimeError):
            mod.build_candidate_crosswalk(candidate, "b" * 64)

    def test_replacement_policy_fails_closed(self):
        candidate = self.candidate()
        candidate["materialization_policy"]["replace_current_crosswalk_authorized"] = True
        with self.assertRaises(RuntimeError):
            mod.build_candidate_crosswalk(candidate, "b" * 64)

    def test_workflow_is_successor_aware_and_preserves_forensic_lock(self):
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        self.assertIn("assert current['destination_count']==96", workflow)
        self.assertNotIn("assert current['destination_count']==56", workflow)
        self.assertIn("LOCKED_READINESS_EVIDENCE", workflow)
        self.assertIn("normalized_live", workflow)
        self.assertIn("normalized_historical", workflow)
        self.assertIn("assert normalized_live==normalized_historical", workflow)
        self.assertNotIn("assert hashlib.sha256(p.read_bytes()).hexdigest()==locked['candidate_json_sha256']", workflow)


if __name__ == "__main__":
    unittest.main()
