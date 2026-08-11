from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "select_wave_seed_cells.py"
SPEC = importlib.util.spec_from_file_location("select_wave_seed_cells", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SelectWaveSeedCellsTests(unittest.TestCase):
    def _write_grid(self, root: Path, zone_id: str, cells: list[dict]) -> None:
        root.mkdir(parents=True, exist_ok=True)
        (root / f"{zone_id}.json").write_text(
            json.dumps(
                {
                    "format": "grand-bruxelles-zone-cells-v2",
                    "zone_id": zone_id,
                    "cells": cells,
                }
            ),
            encoding="utf-8",
        )

    def test_shared_best_cell_is_only_selected_once(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            grids = Path(temp_dir)
            shared = {"id": "bxl-e1000-n1000-s500", "bbox": [1000, 1000, 1500, 1500]}
            self._write_grid(
                grids,
                "a",
                [shared, {"id": "bxl-e500-n1000-s500", "bbox": [500, 1000, 1000, 1500]}],
            )
            self._write_grid(
                grids,
                "b",
                [shared, {"id": "bxl-e1500-n1000-s500", "bbox": [1500, 1000, 2000, 1500]}],
            )
            catalog = {
                "zones": [
                    {"id": "a", "name": "A", "wave": "R", "priority": 1},
                    {"id": "b", "name": "B", "wave": "R", "priority": 2},
                ]
            }
            result = MODULE.select_wave_seeds(catalog, "R", grids, set(), set(), 1250, 1250)
            ids = [seed["cell_id"] for seed in result["seeds"]]
            self.assertEqual(ids[0], shared["id"])
            self.assertEqual(len(ids), len(set(ids)))
            self.assertNotEqual(ids[1], shared["id"])

    def test_existing_and_reserved_cells_are_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            grids = Path(temp_dir)
            cells = [
                {"id": "existing", "bbox": [1000, 1000, 1500, 1500]},
                {"id": "reserved", "bbox": [1500, 1000, 2000, 1500]},
                {"id": "new", "bbox": [2000, 1000, 2500, 1500]},
            ]
            self._write_grid(grids, "a", cells)
            catalog = {"zones": [{"id": "a", "name": "A", "wave": "R", "priority": 1}]}
            result = MODULE.select_wave_seeds(
                catalog,
                "R",
                grids,
                {"existing"},
                {"reserved"},
                1250,
                1250,
            )
            self.assertEqual(result["seeds"][0]["cell_id"], "new")
            self.assertEqual(result["materialized_cell_count_before"], 1)
            self.assertEqual(result["reserved_cell_count"], 1)

    def test_priority_controls_cross_zone_conflict_winner(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            grids = Path(temp_dir)
            shared = {"id": "shared", "bbox": [0, 0, 500, 500]}
            self._write_grid(grids, "later", [shared, {"id": "later-alt", "bbox": [500, 0, 1000, 500]}])
            self._write_grid(grids, "first", [shared, {"id": "first-alt", "bbox": [-500, 0, 0, 500]}])
            catalog = {
                "zones": [
                    {"id": "later", "name": "Later", "wave": "R", "priority": 9},
                    {"id": "first", "name": "First", "wave": "R", "priority": 1},
                ]
            }
            result = MODULE.select_wave_seeds(catalog, "R", grids, set(), set(), 250, 250)
            self.assertEqual([seed["zone_id"] for seed in result["seeds"]], ["first", "later"])
            self.assertEqual(result["seeds"][0]["cell_id"], "shared")
            self.assertNotEqual(result["seeds"][1]["cell_id"], "shared")

    def test_missing_grid_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            catalog = {"zones": [{"id": "missing", "wave": "R", "priority": 1}]}
            with self.assertRaises(ValueError):
                MODULE.select_wave_seeds(catalog, "R", Path(temp_dir), set(), set(), 0, 0)

    def test_load_runtime_exclusions(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "exclusions.json"
            path.write_text(
                json.dumps(
                    {
                        "format": "grand-bruxelles-runtime-exclusions-v1",
                        "excluded_cells": [
                            {"cell_id": "a"},
                            {"cell_id": "b"},
                        ],
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(MODULE.load_excluded_ids(path), {"a", "b"})


if __name__ == "__main__":
    unittest.main()
