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
    def _write_cell(self, root: Path, cell_id: str, bbox: list[float]) -> None:
        cell = root / cell_id
        cell.mkdir()
        manifest = {
            "format": "grand-bruxelles-urbis-built-cell-v1",
            "cell_id": cell_id,
            "bbox": bbox,
            "runtime": {
                "geometry_file": "runtime/cell.game.json",
                "network_file": "runtime/network.game.json",
                "geometry_stats": {"buildings": 12},
                "network_stats": {"street_segments": 8},
            },
        }
        (cell / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

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
            self._write_cell(
                root,
                "bxl-e145500-n169000-s500",
                [145500.0, 169000.0, 146000.0, 169500.0],
            )
            index = MODULE.build_index(root, "res://data/cells")

            self.assertEqual(index["format"], "grand-bruxelles-urbis-runtime-index-v2")
            self.assertEqual(index["cell_count"], 1)
            self.assertEqual(index["excluded_cell_count"], 0)
            item = index["cells"][0]
            self.assertEqual(item["cell_id"], "bxl-e145500-n169000-s500")
            self.assertEqual(
                item["geometry_path"],
                "res://data/cells/bxl-e145500-n169000-s500/runtime/cell.game.json",
            )
            self.assertEqual(
                item["network_path"],
                "res://data/cells/bxl-e145500-n169000-s500/runtime/network.game.json",
            )
            self.assertEqual(len(item["world_center"]), 2)

    def test_reserved_midi_seam_is_retained_on_disk_but_excluded_from_streaming(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            midi_cell = "bxl-e147500-n169500-s500"
            saint_guidon = "bxl-e145500-n169000-s500"
            self._write_cell(root, midi_cell, [147500.0, 169500.0, 148000.0, 170000.0])
            self._write_cell(root, saint_guidon, [145500.0, 169000.0, 146000.0, 169500.0])

            exclusions = {
                midi_cell: {
                    "cell_id": midi_cell,
                    "owner": "main-corridor",
                    "reason": "reserved Midi seam",
                }
            }
            index = MODULE.build_index(root, "res://data/cells", exclusions)

            self.assertEqual(index["cell_count"], 1)
            self.assertEqual(index["excluded_cell_count"], 1)
            self.assertEqual([item["cell_id"] for item in index["cells"]], [saint_guidon])
            self.assertEqual(index["excluded_cells"][0]["cell_id"], midi_cell)
            self.assertEqual(index["excluded_cells"][0]["owner"], "main-corridor")
            self.assertTrue((root / midi_cell / "manifest.json").exists())

    def test_load_exclusions_rejects_duplicate_cell_ids(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "exclusions.json"
            entry = {"cell_id": "bxl-e147500-n169500-s500"}
            path.write_text(
                json.dumps(
                    {
                        "format": "grand-bruxelles-runtime-exclusions-v1",
                        "excluded_cells": [entry, dict(entry)],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                MODULE.load_exclusions(path)

    def test_invalid_manifest_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "manifest.json"
            path.write_text(json.dumps({"format": "wrong"}), encoding="utf-8")
            with self.assertRaises(ValueError):
                MODULE.load_cell_manifest(path)


if __name__ == "__main__":
    unittest.main()
