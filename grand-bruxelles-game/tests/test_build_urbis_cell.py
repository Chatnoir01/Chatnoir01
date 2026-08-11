from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "build_urbis_cell.py"
SPEC = importlib.util.spec_from_file_location("build_urbis_cell", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def fake_layer(layer_name: str, bbox: tuple[float, float, float, float], retries: int) -> dict:
    min_e, min_n, max_e, _ = bbox
    if layer_name.endswith(":Buildings"):
        return {
            "type": "FeatureCollection",
            "features": [
                {
                    "id": "b1",
                    "properties": {"INSPIRE_ID": "b1"},
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[
                            [min_e + 10, min_n + 10],
                            [min_e + 30, min_n + 10],
                            [min_e + 30, min_n + 30],
                            [min_e + 10, min_n + 30],
                            [min_e + 10, min_n + 10],
                        ]],
                    },
                }
            ],
        }
    if layer_name.endswith(":StreetSurfaces"):
        return {
            "type": "FeatureCollection",
            "features": [
                {
                    "id": "s1",
                    "properties": {"INSPIRE_ID": "s1", "TYPE": "S"},
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[
                            [min_e + 50, min_n + 50],
                            [min_e + 70, min_n + 50],
                            [min_e + 70, min_n + 60],
                            [min_e + 50, min_n + 60],
                            [min_e + 50, min_n + 50],
                        ]],
                    },
                }
            ],
        }
    if layer_name.endswith(":StreetAxes"):
        return {
            "type": "FeatureCollection",
            "features": [
                {
                    "id": "r1",
                    "properties": {"INSPIRE_ID": "r1", "STRNAMEFRE": "Rue Test"},
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [[min_e - 10, min_n + 100], [max_e + 10, min_n + 100]],
                    },
                }
            ],
        }
    return {"type": "FeatureCollection", "features": []}


class BuildUrbisCellTests(unittest.TestCase):
    def test_build_cell_writes_raw_geometry_network_and_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "cell"
            bbox = (147500.0, 169500.0, 148000.0, 170000.0)
            with patch.object(MODULE, "request_layer", side_effect=fake_layer):
                manifest = MODULE.build_cell("anderlecht-000-000", bbox, output, retries=2)

            self.assertEqual(manifest["cell_id"], "anderlecht-000-000")
            self.assertTrue((output / "raw" / "buildings.geojson").exists())
            self.assertTrue((output / "raw" / "street_surfaces.geojson").exists())
            self.assertTrue((output / "runtime" / "cell.game.json").exists())
            self.assertTrue((output / "runtime" / "network.game.json").exists())
            self.assertTrue((output / "manifest.json").exists())

            runtime = json.loads((output / "runtime" / "cell.game.json").read_text(encoding="utf-8"))
            network = json.loads((output / "runtime" / "network.game.json").read_text(encoding="utf-8"))
            self.assertEqual(runtime["stats"], {"buildings": 1, "street_surfaces": 1})
            self.assertTrue(runtime["coordinate_system"]["coordinates_are_current_game_world"])
            self.assertEqual(network["stats"]["street_segments"], 1)
            self.assertEqual(manifest["runtime"]["geometry_file"], "runtime/cell.game.json")
            self.assertEqual(manifest["runtime"]["network_file"], "runtime/network.game.json")

    def test_all_configured_wfs_layers_are_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output = Path(temp_dir) / "cell"
            bbox = (147500.0, 169500.0, 148000.0, 170000.0)
            with patch.object(MODULE, "request_layer", side_effect=fake_layer) as mocked:
                manifest = MODULE.build_cell("test", bbox, output)
            self.assertEqual(mocked.call_count, len(MODULE.DEFAULT_LAYERS))
            self.assertEqual(set(manifest["layers"]), set(MODULE.DEFAULT_LAYERS))


if __name__ == "__main__":
    unittest.main()
