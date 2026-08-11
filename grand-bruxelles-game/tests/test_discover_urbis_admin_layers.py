from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "discover_urbis_admin_layers.py"
SPEC = importlib.util.spec_from_file_location("discover_urbis_admin_layers", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


CAPABILITIES = b'''<?xml version="1.0" encoding="UTF-8"?>
<wfs:WFS_Capabilities xmlns:wfs="http://www.opengis.net/wfs/2.0">
  <wfs:FeatureTypeList>
    <wfs:FeatureType>
      <wfs:Name>urbisvector:Buildings</wfs:Name>
      <wfs:Title>Buildings</wfs:Title>
      <wfs:DefaultCRS>urn:ogc:def:crs:EPSG::31370</wfs:DefaultCRS>
    </wfs:FeatureType>
    <wfs:FeatureType>
      <wfs:Name>urbisvector:AdministrativeDistricts</wfs:Name>
      <wfs:Title>Administrative districts</wfs:Title>
      <wfs:Abstract>Official municipal district limits</wfs:Abstract>
      <wfs:DefaultCRS>urn:ogc:def:crs:EPSG::31370</wfs:DefaultCRS>
    </wfs:FeatureType>
    <wfs:FeatureType>
      <wfs:Name>urbisvector:StatisticalSectors</wfs:Name>
      <wfs:Title>Statistical sectors</wfs:Title>
      <wfs:DefaultCRS>urn:ogc:def:crs:EPSG::31370</wfs:DefaultCRS>
    </wfs:FeatureType>
  </wfs:FeatureTypeList>
</wfs:WFS_Capabilities>
'''


class DiscoverUrbisAdminLayersTests(unittest.TestCase):
    def test_only_keyword_matching_feature_types_are_returned(self) -> None:
        candidates = MODULE.parse_feature_types(CAPABILITIES)
        self.assertEqual(
            [candidate["name"] for candidate in candidates],
            [
                "urbisvector:AdministrativeDistricts",
                "urbisvector:StatisticalSectors",
            ],
        )
        self.assertIn("admin", candidates[0]["matched_keywords"])
        self.assertIn("district", candidates[0]["matched_keywords"])
        self.assertIn("stat", candidates[1]["matched_keywords"])
        self.assertEqual(
            candidates[0]["default_crs"],
            "urn:ogc:def:crs:EPSG::31370",
        )

    def test_build_manifest_never_marks_candidates_production_approved(self) -> None:
        manifest = MODULE.build_manifest(CAPABILITIES, "https://example.invalid/wfs")
        self.assertEqual(
            manifest["format"],
            "grand-bruxelles-urbis-admin-layer-discovery-v1",
        )
        self.assertEqual(manifest["candidate_count"], 2)
        self.assertIn("not production-approved", manifest["purpose"])
        self.assertNotIn("production_approved", manifest)

    def test_malformed_xml_is_rejected(self) -> None:
        with self.assertRaises(Exception):
            MODULE.parse_feature_types(b"<broken")


if __name__ == "__main__":
    unittest.main()
