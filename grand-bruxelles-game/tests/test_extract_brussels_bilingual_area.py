from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "extract_brussels_bilingual_area.py"
SPEC = importlib.util.spec_from_file_location("extract_brussels_bilingual_area", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


POLY = {"type": "Polygon", "coordinates": [[[148000,170000],[148500,170000],[148500,170500],[148000,170500],[148000,170000]]]}


class ExtractBrusselsBilingualAreaTests(unittest.TestCase):
    def test_identical_bilingual_records_produce_one_canonical_set(self) -> None:
        records = [{"name_fr": "Pentagone", "name_nl": "Vijfhoek", "shape": POLY}]
        features, evidence = MODULE.canonical_features(records, ["pentagone", "vijfhoek"])
        self.assertEqual(len(features), 1)
        self.assertEqual(features[0]["properties"]["canonical_labels"], ["pentagone", "vijfhoek"])
        self.assertEqual(evidence["geometry_fingerprint_count"], 1)

    def test_different_geometries_are_rejected(self) -> None:
        records = [
            {"name": "Pentagone", "shape": POLY},
            {"name": "Vijfhoek", "shape": {"type": "Polygon", "coordinates": [[[149000,170000],[149500,170000],[149500,170500],[149000,170500],[149000,170000]]]}},
        ]
        with self.assertRaises(ValueError):
            MODULE.canonical_features(records, ["pentagone", "vijfhoek"])

    def test_build_output_requires_same_license_approved_dataset(self) -> None:
        probe = {
            "datasets_with_polygon_match_by_target": {
                "pentagone": ["areas"],
                "vijfhoek": ["areas"],
            }
        }
        selection = {
            "dataset_id": "other",
            "license": "CC BY 4.0",
            "license_gate": {"production_geometry_allowed": True},
        }
        records = [{"fr": "Pentagone", "nl": "Vijfhoek", "shape": POLY}]
        with self.assertRaises(ValueError):
            MODULE.build_output(probe, selection, records, ["pentagone", "vijfhoek"])

    def test_build_output_requires_positive_license_gate(self) -> None:
        probe = {
            "datasets_with_polygon_match_by_target": {
                "pentagone": ["areas"],
                "vijfhoek": ["areas"],
            }
        }
        selection = {
            "dataset_id": "areas",
            "license": "unknown",
            "license_gate": {"production_geometry_allowed": False},
        }
        records = [{"fr": "Pentagone", "nl": "Vijfhoek", "shape": POLY}]
        with self.assertRaises(ValueError):
            MODULE.build_output(probe, selection, records, ["pentagone", "vijfhoek"])


if __name__ == "__main__":
    unittest.main()
