from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "extract_brussels_opendata_subzones.py"
SPEC = importlib.util.spec_from_file_location("extract_brussels_opendata_subzones", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ExtractBrusselsOpenDataSubzonesTests(unittest.TestCase):
    def test_common_dataset_requires_one_shared_proven_dataset(self) -> None:
        probe = {
            "datasets_with_polygon_match_by_target": {
                "quartier européen": ["areas"],
                "louise": ["areas", "other"],
                "bois de la cambre": ["areas"],
            }
        }
        self.assertEqual(
            MODULE.common_dataset(probe, ["quartier européen", "louise", "bois de la cambre"]),
            "areas",
        )

    def test_missing_shared_dataset_is_rejected(self) -> None:
        probe = {"datasets_with_polygon_match_by_target": {"a": ["x"], "b": ["y"]}}
        with self.assertRaises(ValueError):
            MODULE.common_dataset(probe, ["a", "b"])

    def test_crs_detection_distinguishes_wgs84_and_lambert72(self) -> None:
        wgs = {"type": "Polygon", "coordinates": [[[4.35,50.83],[4.36,50.83],[4.36,50.84],[4.35,50.84],[4.35,50.83]]]}
        lambert = {"type": "Polygon", "coordinates": [[[148000,170000],[149000,170000],[149000,171000],[148000,171000],[148000,170000]]]}
        self.assertEqual(MODULE.detect_crs(wgs), "EPSG:4326")
        self.assertEqual(MODULE.detect_crs(lambert), "EPSG:31370")

    def test_lambert_geometry_is_preserved_without_pyproj(self) -> None:
        geometry = {"type": "Polygon", "coordinates": [[[148000,170000],[149000,170000],[149000,171000],[148000,171000],[148000,170000]]]}
        result, source = MODULE.to_lambert72(geometry)
        self.assertEqual(source, "EPSG:31370")
        self.assertEqual(result, geometry)
        self.assertIsNot(result, geometry)

    def test_named_record_produces_feature_only_when_polygon_is_present(self) -> None:
        records = [
            {"name": "Louise", "shape": {"type": "Polygon", "coordinates": [[[148000,170000],[149000,170000],[149000,171000],[148000,171000],[148000,170000]]]}},
            {"name": "Louise", "point": {"lon": 4.35, "lat": 50.83}},
        ]
        features, crs_values = MODULE.target_features(records, "louise")
        self.assertEqual(len(features), 1)
        self.assertEqual(crs_values, {"EPSG:31370"})
        self.assertEqual(features[0]["properties"]["matching_fields"]["name"], "Louise")

    def test_unknown_coordinate_range_is_rejected(self) -> None:
        geometry = {"type": "Polygon", "coordinates": [[[999999,999999],[1000000,999999],[1000000,1000000],[999999,1000000],[999999,999999]]]}
        with self.assertRaises(ValueError):
            MODULE.detect_crs(geometry)


if __name__ == "__main__":
    unittest.main()
