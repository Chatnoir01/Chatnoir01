from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "build_urbis_runtime_index.py"
SPEC = importlib.util.spec_from_file_location("build_urbis_runtime_index", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BuildUrbisRuntimeIndexTests(unittest.TestCase):
    def test_world_bounds_include_current_midi_anchor(self) -> None:
        bounds = MODULE.world_bounds([
            MODULE.game_point.__globals__["ORIGIN_E"],
            MODULE.game_point.__globals__["ORIGIN_N"],
            MODULE.game_point.__globals__["ORIGIN_E"] + 500.0,
            MODULE.game_point.__globals__["ORIGIN_N"] + 500.0,
        ])
        self.assertEqual(bounds[0], -668.5)
        self.assertEqual(bounds[3], 627.84)
        self.assertEqual(bounds[2], -168.5)
        self.assertEqual(bounds[1], 127.84)

    def test_index_builds_resource_paths_and_centers(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            cell = root / "anderlecht-000-000"
            cell.mkdir()
            manifest = {
                "format": "grand-bruxelles-urbis-built-cell-v1",
                "cell_id": "anderlecht-000-000",
                "bbox": [147500.0, 169500.0, 148000.0, 170000.0],
                "runtime": {
                    "geometry_file": "runtime/cell.game.json",
                    "network_file": "runtime/network.game.json",
                    "geometry_stats": {"buildings": 12},
                    "network_stats": {"street_segments": 8},
                },
            }
            (cell / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            index = MODULE.build_index(root, "res://data/cells")

            self.assertEqual(index["cell_count"], 1)
            item = index["cells"][0]
            self.assertEqual(item["cell_id"], "anderlecht-000-000")
            self.assertEqual(
                item["geometry_path"],
                "res://data/cells/anderlecht-000-000/runtime/cell.game.json",
            )
            self.assertEqual(
                item["network_path"],
                "res://data/cells/anderlecht-000-000/runtime/network.game.json",
            )
            self.assertEqual(len(item["world_center"]), 2)

    def test_invalid_manifest_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "manifest.json"
            path.write_text(json.dumps({"format": "wrong"}), encoding="utf-8")
            with self.assertRaises(ValueError):
                MODULE.load_cell_manifest(path)


if __name__ == "__main__":
    unittest.main()
