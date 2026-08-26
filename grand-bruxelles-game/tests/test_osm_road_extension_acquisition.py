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
        # The segment bbox overlaps the cell bbox, but the diagonal itself stays
        # entirely below-left of the rectangle. The old extent-only test returned
        # True here and could falsely prove road coverage.
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
        self.assertEqual(contract["target"]["crs"], "EPSG:31370")
        self.assertEqual(contract["source"]["license"], "ODbL-1.0")
        self.assertTrue(contract["authorization"])
        self.assertTrue(all(value is False for value in contract["authorization"].values()))

    def test_transport_fallback_is_bounded_and_explicit(self):
        contract = json.loads(Path("data/qa/osm_road_extension_e148500_n170500.contract.json").read_text())
        source = contract["source"]
        endpoints = source["endpoints"]
        self.assertGreaterEqual(len(endpoints), 2)
        self.assertEqual(endpoints[0], source["endpoint"])
        self.assertEqual(len(endpoints), len(set(endpoints)))
        self.assertTrue(all(v.startswith("https://") and v.endswith("/api/interpreter") for v in endpoints))
        self.assertGreaterEqual(source["transport_attempts_per_endpoint"], 1)
        self.assertLessEqual(source["transport_attempts_per_endpoint"], 3)
        self.assertGreater(source["transport_max_time_seconds"], source["overpass_timeout_seconds"])
        self.assertLessEqual(source["transport_max_time_seconds"], 120)

    def test_workflow_never_parses_failed_transport_as_payload(self):
        workflow = Path("../.github/workflows/grand-bruxelles-osm-road-extension-e148500-n170500.yml").read_text()
        self.assertIn('candidate="${RUNNER_TEMP}/overpass.raw.${endpoint_index}.${attempt}.json"', workflow)
        self.assertIn('if curl ', workflow)
        self.assertIn('python - "$candidate"', workflow)
        self.assertIn('mv "$candidate" "$RUNNER_TEMP/overpass.raw.json"', workflow)
        self.assertIn('test "$acquired" = true', workflow)
        self.assertNotIn('> "$RUNNER_TEMP/overpass.raw.json"\n          python -m json.tool', workflow)


if __name__ == "__main__":
    unittest.main()
