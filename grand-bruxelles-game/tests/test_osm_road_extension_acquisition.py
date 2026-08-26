import json
import unittest
from pathlib import Path

from tools.qa.acquire_osm_road_extension_candidate import canonical_json, sha256_bytes, segment_bbox_intersects


class OsmRoadExtensionAcquisitionTests(unittest.TestCase):
    def test_segment_bbox_intersection(self):
        bbox = [148500.0, 170500.0, 149000.0, 171000.0]
        self.assertTrue(segment_bbox_intersects((148400.0, 170750.0), (148600.0, 170750.0), bbox))
        self.assertFalse(segment_bbox_intersects((147000.0, 169000.0), (147500.0, 169500.0), bbox))

    def test_segment_bbox_intersection_rejects_extent_only_false_positive(self):
        bbox = [2.5, 2.5, 3.0, 3.0]
        self.assertFalse(segment_bbox_intersects((0.0, 3.0), (3.0, 0.0), bbox))

    def test_segment_bbox_intersection_accepts_boundary_touch(self):
        bbox = [2.5, 2.5, 3.0, 3.0]
        self.assertTrue(segment_bbox_intersects((2.0, 2.0), (2.5, 2.5), bbox))

    def test_segment_bbox_intersection_handles_parallel_segments(self):
        bbox = [10.0, 10.0, 20.0, 20.0]
        self.assertTrue(segment_bbox_intersects((10.0, 15.0), (20.0, 15.0), bbox))
        self.assertFalse(segment_bbox_intersects((10.0, 25.0), (20.0, 25.0), bbox))

    def test_canonical_digest_ignores_mapping_order(self):
        a = {"b": 2, "a": 1}
        b = {"a": 1, "b": 2}
        self.assertEqual(sha256_bytes(canonical_json(a)), sha256_bytes(canonical_json(b)))

    def test_closed_authorization_contract(self):
        contract = json.loads(Path("data/qa/osm_road_extension_e148500_n170500.contract.json").read_text())
        self.assertEqual(contract["schema"], "grand-bruxelles-osm-road-extension-acquisition-v2")
        self.assertEqual(contract["status"], "LOCKED_SOURCE_ONLY_ARTIFACT")
        self.assertEqual(contract["target"]["crs"], "EPSG:31370")
        self.assertEqual(contract["source"]["license"], "ODbL-1.0")
        self.assertTrue(contract["authorization"])
        self.assertTrue(all(value is False for value in contract["authorization"].values()))

    def test_locked_artifact_identity_is_complete(self):
        contract = json.loads(Path("data/qa/osm_road_extension_e148500_n170500.contract.json").read_text())
        evidence = contract["locked_evidence"]
        self.assertEqual(evidence["workflow_run_id"], 32997864824)
        self.assertEqual(evidence["artifact_id"], 9617302727)
        self.assertEqual(evidence["artifact_zip_bytes"], 79621)
        self.assertEqual(evidence["artifact_zip_sha256"], "8e5bd2508c5827cb9d14dc4a319044cbc6fbe2f96ed14fbca06b4db6e79933e3")
        self.assertEqual(evidence["measurement_sha256"], "f372f418a0e8c64f90558fb15a901a187a3171f83e5a25c7091d441f0ca22fe8")
        self.assertEqual(evidence["raw_bytes"], 538236)
        self.assertEqual(evidence["raw_sha256"], "80544caed58414f3f3c58274659fcb9ec9487621976c263843af7c59d007b4ab")
        self.assertEqual(evidence["semantic_sha256"], "7264a311b7688350126a9faa4a1e16eab7e7eea0cbc231217c3080488d7a41bf")
        self.assertEqual(evidence["accounting"]["highway_way_count"], 591)
        self.assertEqual(evidence["accounting"]["referenced_node_count"], 3508)
        self.assertEqual(evidence["accounting"]["way_point_count"], 4568)
        self.assertEqual(evidence["accounting"]["target_intersecting_way_count"], 591)

    def test_locked_phase_workflow_is_artifact_only(self):
        workflow = Path("../.github/workflows/grand-bruxelles-osm-road-extension-e148500-n170500.yml").read_text()
        self.assertIn("actions/artifacts/9617302727/zip", workflow)
        self.assertIn("8e5bd2508c5827cb9d14dc4a319044cbc6fbe2f96ed14fbca06b4db6e79933e3", workflow)
        self.assertIn("Reproduce measurement from immutable artifact only", workflow)
        self.assertIn("cmp \"$RUNNER_TEMP/locked_source/osm_road_extension_e148500_n170500.measurement.json\"", workflow)
        self.assertNotIn("Build exact Overpass query from Lambert72 target cell", workflow)
        self.assertNotIn("Acquire OSM road extension candidate with bounded endpoint failover", workflow)
        self.assertNotIn("--data-urlencode", workflow)
        self.assertNotIn("overpass.kumi.systems/api/interpreter\" >", workflow)


if __name__ == "__main__":
    unittest.main()
