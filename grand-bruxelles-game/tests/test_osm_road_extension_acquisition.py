import json
import tempfile
import unittest
from pathlib import Path

from tools.qa.acquire_osm_road_extension_candidate import canonical_json, sha256_bytes, segment_bbox_intersects


class OsmRoadExtensionAcquisitionTests(unittest.TestCase):
    def test_segment_bbox_intersection(self):
        bbox = [148500.0, 170500.0, 149000.0, 171000.0]
        self.assertTrue(segment_bbox_intersects((148400.0, 170750.0), (148600.0, 170750.0), bbox))
        self.assertFalse(segment_bbox_intersects((147000.0, 169000.0), (147500.0, 169500.0), bbox))

    def test_canonical_digest_ignores_mapping_order(self):
        a = {"b": 2, "a": 1}
        b = {"a": 1, "b": 2}
        self.assertEqual(sha256_bytes(canonical_json(a)), sha256_bytes(canonical_json(b)))

    def test_closed_authorization_contract(self):
        contract = json.loads(Path("data/qa/osm_road_extension_e148500_n170500.contract.json").read_text())
        self.assertEqual(contract["target"]["crs"], "EPSG:31370")
        self.assertEqual(contract["source"]["license"], "ODbL-1.0")
        self.assertTrue(contract["authorization"])
        self.assertTrue(all(value is False for value in contract["authorization"].values()))


if __name__ == "__main__":
    unittest.main()
