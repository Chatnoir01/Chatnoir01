from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "probe_brussels_opendata_boundaries.py"
SPEC = importlib.util.spec_from_file_location("probe_brussels_opendata_boundaries", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProbeBrusselsOpenDataBoundariesTests(unittest.TestCase):
    def test_matching_tolerates_accents_and_spacing(self) -> None:
        self.assertTrue(MODULE.scalar_match("Quartier Européen", "quartier européen"))
        self.assertTrue(MODULE.scalar_match("BOIS-DE-LA-CAMBRE", "bois de la cambre"))
        self.assertTrue(MODULE.scalar_match("Avenue Louise / Louizalaan", "louise"))
        self.assertFalse(MODULE.scalar_match("Haren", "louise"))

    def test_polygon_geometry_is_found_nested_in_record(self) -> None:
        record = {
            "name": "Quartier Européen",
            "geo_shape": {
                "type": "Feature",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[[4.3, 50.8], [4.4, 50.8], [4.4, 50.9], [4.3, 50.9], [4.3, 50.8]]],
                },
            },
        }
        found = list(MODULE.iter_polygon_geometries(record))
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0][1]["type"], "Polygon")
        self.assertEqual(MODULE.geometry_bbox(found[0][1]), [4.3, 50.8, 4.4, 50.9])

    def test_point_only_name_match_is_not_boundary_evidence(self) -> None:
        records = [
            {"name": "Louise", "geo_point_2d": {"lon": 4.36, "lat": 50.83}},
            {"name": "Other", "geo_shape": {"type": "Polygon", "coordinates": [[[1,1],[2,1],[2,2],[1,2],[1,1]]]}}
        ]
        result = MODULE.inspect_records("dataset", records, ["louise"])
        self.assertEqual(result["matched_polygon_targets"], [])
        self.assertEqual(result["target_matches"]["louise"], [])

    def test_same_record_must_contain_name_and_polygon(self) -> None:
        records = [
            {
                "name": "Bois de la Cambre",
                "shape": {"type": "MultiPolygon", "coordinates": [[[[1,1],[2,1],[2,2],[1,2],[1,1]]]]},
            }
        ]
        result = MODULE.inspect_records("areas", records, ["bois de la cambre", "louise"])
        self.assertEqual(result["matched_polygon_targets"], ["bois de la cambre"])
        self.assertIn("name", result["target_matches"]["bois de la cambre"][0]["matching_fields"])

    def test_records_url_uses_official_dataset_endpoint(self) -> None:
        url = MODULE.records_url("my dataset", 100, 200)
        self.assertTrue(url.startswith("https://opendata.brussels.be/api/explore/v2.1/catalog/datasets/"))
        self.assertIn("my%20dataset", url)
        self.assertIn("limit=100", url)
        self.assertIn("offset=200", url)


if __name__ == "__main__":
    unittest.main()
