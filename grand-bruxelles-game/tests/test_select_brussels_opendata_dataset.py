from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "select_brussels_opendata_dataset.py"
SPEC = importlib.util.spec_from_file_location("select_brussels_opendata_dataset", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SelectBrusselsOpenDataDatasetTests(unittest.TestCase):
    def test_open_license_allowlist_is_conservative(self) -> None:
        self.assertEqual(MODULE.license_gate("CC BY 4.0"), (True, "cc by"))
        self.assertEqual(MODULE.license_gate("Open Data Licence"), (True, "open data licence"))
        self.assertEqual(MODULE.license_gate("Custom restrictive terms"), (False, None))
        self.assertEqual(MODULE.license_gate(""), (False, None))

    def test_one_common_dataset_is_selected(self) -> None:
        discovery = {
            "format": MODULE.DISCOVERY_FORMAT,
            "candidates": [
                {"dataset_id": "areas", "title": "Areas", "publisher": "Brussels", "license": "CC BY 4.0", "records_count": 100},
                {"dataset_id": "other", "title": "Other", "publisher": "Brussels", "license": "", "records_count": 3},
            ],
        }
        probe = {
            "format": MODULE.PROBE_FORMAT,
            "datasets_with_polygon_match_by_target": {
                "quartier européen": ["areas"],
                "louise": ["areas", "other"],
                "roosevelt": ["areas"],
                "bois de la cambre": ["areas"],
            },
        }
        result = MODULE.select_dataset(discovery, probe, list(MODULE.DEFAULT_TARGETS))
        self.assertEqual(result["dataset_id"], "areas")
        self.assertTrue(result["polygon_name_proof"])
        self.assertTrue(result["license_gate"]["production_geometry_allowed"])
        self.assertTrue(result["license_gate"]["not_legal_opinion"])

    def test_unknown_license_blocks_production_geometry(self) -> None:
        discovery = {
            "candidates": [{"dataset_id": "areas", "license": "bespoke terms"}],
        }
        probe = {
            "datasets_with_polygon_match_by_target": {
                "a": ["areas"],
                "b": ["areas"],
            },
        }
        result = MODULE.select_dataset(discovery, probe, ["a", "b"])
        self.assertFalse(result["license_gate"]["production_geometry_allowed"])

    def test_ambiguous_common_dataset_is_rejected(self) -> None:
        probe = {"datasets_with_polygon_match_by_target": {"a": ["x", "y"], "b": ["x", "y"]}}
        with self.assertRaises(ValueError):
            MODULE.common_dataset(probe, ["a", "b"])


if __name__ == "__main__":
    unittest.main()
