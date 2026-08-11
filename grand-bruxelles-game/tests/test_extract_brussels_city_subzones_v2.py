from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "extract_brussels_city_subzones_v2.py"
SPEC = importlib.util.spec_from_file_location("extract_brussels_city_subzones_v2", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def probe() -> dict:
    return {
        "format": "grand-bruxelles-urbis-admin-layer-probe-v1",
        "targets": ["haren", "neder-over-heembeek"],
        "proven_layers_matching_all_targets": ["urbisvector:Admin"],
        "results": [{
            "layer": "urbisvector:Admin",
            "status": "inspected",
            "target_matches": {
                "haren": [{"matching_properties": {"NAME_FRE": "Haren"}}],
                "neder-over-heembeek": [{"matching_properties": {"NAME_FRE": "Neder-over-Heembeek"}}],
            },
        }],
    }


class ExtractBrusselsCitySubzonesV2Tests(unittest.TestCase):
    def test_extra_laeken_target_uses_proven_name_key(self) -> None:
        document = {
            "type": "FeatureCollection",
            "features": [
                {"id": "h", "properties": {"NAME_FRE": "Haren"}, "geometry": {"type": "Polygon", "coordinates": [[[0,0],[1,0],[1,1],[0,1],[0,0]]]}},
                {"id": "n", "properties": {"NAME_FRE": "Neder-over-Heembeek"}, "geometry": {"type": "Polygon", "coordinates": [[[2,0],[3,0],[3,1],[2,1],[2,0]]]}},
                {"id": "l", "properties": {"NAME_FRE": "Laeken"}, "geometry": {"type": "MultiPolygon", "coordinates": [[[[4,0],[5,0],[5,1],[4,1],[4,0]]]]}},
            ],
        }
        outputs, manifest = MODULE.build_outputs_v2(
            probe(), document, ["haren", "neder-over-heembeek", "laeken"]
        )
        self.assertEqual(set(outputs), {"haren", "neder-over-heembeek", "laeken"})
        self.assertEqual(outputs["laeken"]["features"][0]["id"], "l")
        self.assertFalse(manifest["targets"]["laeken"]["schema_proof_target"])
        self.assertEqual(manifest["proven_name_property_keys"], ["NAME_FRE"])

    def test_unknown_extra_target_is_rejected(self) -> None:
        document = {
            "type": "FeatureCollection",
            "features": [
                {"id": "h", "properties": {"NAME_FRE": "Haren"}, "geometry": {"type": "Polygon", "coordinates": [[[0,0],[1,0],[1,1],[0,1],[0,0]]]}},
                {"id": "n", "properties": {"NAME_FRE": "Neder-over-Heembeek"}, "geometry": {"type": "Polygon", "coordinates": [[[2,0],[3,0],[3,1],[2,1],[2,0]]]}},
            ],
        }
        with self.assertRaises(ValueError):
            MODULE.build_outputs_v2(probe(), document, ["laeken"])

    def test_probe_targets_are_recorded_as_schema_proof(self) -> None:
        document = {
            "type": "FeatureCollection",
            "features": [
                {"id": "h", "properties": {"NAME_FRE": "Haren"}, "geometry": {"type": "Polygon", "coordinates": [[[0,0],[1,0],[1,1],[0,1],[0,0]]]}},
                {"id": "n", "properties": {"NAME_FRE": "Neder-over-Heembeek"}, "geometry": {"type": "Polygon", "coordinates": [[[2,0],[3,0],[3,1],[2,1],[2,0]]]}},
            ],
        }
        _, manifest = MODULE.build_outputs_v2(probe(), document, ["haren", "neder-over-heembeek"])
        self.assertTrue(manifest["targets"]["haren"]["schema_proof_target"])
        self.assertTrue(manifest["targets"]["neder-over-heembeek"]["schema_proof_target"])


if __name__ == "__main__":
    unittest.main()
