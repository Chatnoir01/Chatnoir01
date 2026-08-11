from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "probe_urbis_admin_layers.py"
SPEC = importlib.util.spec_from_file_location("probe_urbis_admin_layers", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProbeUrbisAdminLayersTests(unittest.TestCase):
    def test_name_matching_tolerates_punctuation(self) -> None:
        self.assertTrue(MODULE.value_matches("Neder-Over-Heembeek", "neder-over-heembeek"))
        self.assertTrue(MODULE.value_matches("NEDER OVER HEEMBEEK", "neder-over-heembeek"))
        self.assertTrue(MODULE.value_matches("Haren / Haeren", "haren"))
        self.assertFalse(MODULE.value_matches("Laeken", "haren"))

    def test_document_proves_targets_from_real_attributes_not_layer_name(self) -> None:
        doc = {
            "type": "FeatureCollection",
            "features": [
                {"id": "a", "properties": {"NAME_FRE": "Haren"}, "geometry": {"type": "Polygon", "coordinates": [[[1,2],[3,2],[3,4],[1,4],[1,2]]]}},
                {"id": "b", "properties": {"NAME_FRE": "Neder-over-Heembeek"}, "geometry": {"type": "Polygon", "coordinates": [[[5,6],[7,6],[7,8],[5,8],[5,6]]]}},
            ],
        }
        result = MODULE.inspect_document("urbisvector:Anything", doc, ["haren", "neder-over-heembeek"])
        self.assertEqual(result["matched_targets"], ["haren", "neder-over-heembeek"])
        self.assertEqual(result["target_matches"]["haren"][0]["geometry_bbox"], [1.0, 2.0, 3.0, 4.0])
        self.assertIn("NAME_FRE", result["target_matches"]["neder-over-heembeek"][0]["matching_properties"])

    def test_matching_properties_ignores_nested_values(self) -> None:
        props = {"name": "Haren", "nested": {"name": "Haren"}, "list": ["Haren"]}
        self.assertEqual(MODULE.matching_properties(props, "haren"), {"name": "Haren"})

    def test_geometry_bbox_handles_empty_geometry(self) -> None:
        self.assertIsNone(MODULE.geometry_bbox(None))
        self.assertIsNone(MODULE.geometry_bbox({"type": "Polygon", "coordinates": []}))


if __name__ == "__main__":
    unittest.main()
