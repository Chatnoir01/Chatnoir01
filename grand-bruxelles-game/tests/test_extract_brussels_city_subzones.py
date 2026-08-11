from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "extract_brussels_city_subzones.py"
SPEC = importlib.util.spec_from_file_location("extract_brussels_city_subzones", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def probe() -> dict:
    return {
        "format": MODULE.PROBE_FORMAT,
        "targets": ["haren", "neder-over-heembeek"],
        "proven_layers_matching_all_targets": ["urbisvector:Admin"],
        "results": [
            {
                "layer": "urbisvector:Admin",
                "status": "inspected",
                "target_matches": {
                    "haren": [{"matching_properties": {"NAME_FRE": "Haren", "NAME_DUT": "Haren"}}],
                    "neder-over-heembeek": [{"matching_properties": {"NAME_FRE": "Neder-over-Heembeek"}}],
                },
            }
        ],
    }


class ExtractBrusselsCitySubzonesTests(unittest.TestCase):
    def test_shared_proven_name_key_is_required(self) -> None:
        result = MODULE.proven_result(probe())
        self.assertEqual(
            MODULE.proven_name_keys(result, ["haren", "neder-over-heembeek"]),
            {"NAME_FRE"},
        )

    def test_polygon_targets_are_extracted_and_manifested(self) -> None:
        document = {
            "type": "FeatureCollection",
            "features": [
                {"id": "h", "properties": {"NAME_FRE": "Haren"}, "geometry": {"type": "Polygon", "coordinates": [[[1,1],[2,1],[2,2],[1,2],[1,1]]]}},
                {"id": "n", "properties": {"NAME_FRE": "Neder-over-Heembeek"}, "geometry": {"type": "MultiPolygon", "coordinates": [[[[3,3],[4,3],[4,4],[3,4],[3,3]]]]}},
                {"id": "l", "properties": {"NAME_FRE": "Laeken"}, "geometry": {"type": "Polygon", "coordinates": [[[5,5],[6,5],[6,6],[5,6],[5,5]]]}},
            ],
        }
        outputs, manifest = MODULE.build_outputs(probe(), document, ["haren", "neder-over-heembeek"])
        self.assertEqual(set(outputs), {"haren", "neder-over-heembeek"})
        self.assertEqual(len(outputs["haren"]["features"]), 1)
        self.assertEqual(outputs["haren"]["features"][0]["id"], "h")
        self.assertEqual(manifest["source_layer"], "urbisvector:Admin")
        self.assertTrue(manifest["production_gate"]["cell_grid_generation_allowed"])

    def test_non_polygon_match_is_rejected(self) -> None:
        document = {
            "features": [
                {"id": "h", "properties": {"NAME_FRE": "Haren"}, "geometry": {"type": "Point", "coordinates": [1,2]}}
            ]
        }
        with self.assertRaises(ValueError):
            MODULE.extract_target_features(document, "haren", {"NAME_FRE"})

    def test_probe_requires_exactly_one_proven_layer(self) -> None:
        p = probe()
        p["proven_layers_matching_all_targets"] = ["a", "b"]
        with self.assertRaises(ValueError):
            MODULE.proven_result(p)


if __name__ == "__main__":
    unittest.main()
