from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "select_uncovered_zone_seeds.py"
SPEC = importlib.util.spec_from_file_location("select_uncovered_zone_seeds", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SelectUncoveredZoneSeedsTests(unittest.TestCase):
    def _write_grid(self, root: Path, zone_id: str, source_bbox: list[float], cells: list[dict]) -> None:
        root.mkdir(parents=True, exist_ok=True)
        (root / f"{zone_id}.json").write_text(
            json.dumps(
                {
                    "format": "grand-bruxelles-zone-cells-v2",
                    "zone_id": zone_id,
                    "source_bbox": source_bbox,
                    "cells": cells,
                }
            ),
            encoding="utf-8",
        )

    def test_only_zero_materialized_zone_receives_seed(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            grids = Path(temp_dir)
            self._write_grid(
                grids,
                "covered",
                [0, 0, 1000, 1000],
                [{"id": "bxl-e0-n0-s500", "bbox": [0, 0, 500, 500]}],
            )
            self._write_grid(
                grids,
                "empty",
                [1000, 1000, 2000, 2000],
                [
                    {"id": "bxl-e1000-n1000-s500", "bbox": [1000, 1000, 1500, 1500]},
                    {"id": "bxl-e1500-n1500-s500", "bbox": [1500, 1500, 2000, 2000]},
                ],
            )
            catalog = {
                "zones": [
                    {"id": "covered", "name": "Covered", "wave": "R1", "priority": 1},
                    {"id": "empty", "name": "Empty", "wave": "R1", "priority": 2},
                ]
            }
            coverage = {
                "zones": [
                    {"zone_id": "covered", "grid_ready": True, "materialized_cells": 1},
                    {"zone_id": "empty", "grid_ready": True, "materialized_cells": 0},
                ]
            }
            result = MODULE.select_uncovered(catalog, coverage, grids, {"bxl-e0-n0-s500"}, set())
            self.assertEqual(result["seed_count"], 1)
            self.assertEqual(result["seeds"][0]["zone_id"], "empty")
            self.assertEqual(result["skipped_already_covered_zone_ids"], ["covered"])
            self.assertEqual(result["seeds"][0]["anchor"], [1500.0, 1500.0])
            self.assertEqual(result["seeds"][0]["anchor_kind"], "official_boundary_bbox_center")

    def test_reserved_center_cell_is_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            grids = Path(temp_dir)
            self._write_grid(
                grids,
                "empty",
                [0, 0, 1000, 1000],
                [
                    {"id": "bxl-e0-n0-s500", "bbox": [0, 0, 500, 500]},
                    {"id": "bxl-e500-n500-s500", "bbox": [500, 500, 1000, 1000]},
                ],
            )
            catalog = {"zones": [{"id": "empty", "wave": "R1", "priority": 1}]}
            coverage = {"zones": [{"zone_id": "empty", "grid_ready": True, "materialized_cells": 0}]}
            result = MODULE.select_uncovered(
                catalog,
                coverage,
                grids,
                set(),
                {"bxl-e500-n500-s500"},
            )
            self.assertEqual(result["seeds"][0]["cell_id"], "bxl-e0-n0-s500")

    def test_shared_cell_is_not_selected_twice(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            grids = Path(temp_dir)
            shared = {"id": "bxl-e500-n500-s500", "bbox": [500, 500, 1000, 1000]}
            self._write_grid(
                grids,
                "a",
                [0, 0, 1000, 1000],
                [shared, {"id": "bxl-e0-n0-s500", "bbox": [0, 0, 500, 500]}],
            )
            self._write_grid(
                grids,
                "b",
                [500, 500, 1500, 1500],
                [shared, {"id": "bxl-e1000-n1000-s500", "bbox": [1000, 1000, 1500, 1500]}],
            )
            catalog = {
                "zones": [
                    {"id": "a", "wave": "R1", "priority": 1},
                    {"id": "b", "wave": "R1", "priority": 2},
                ]
            }
            coverage = {
                "zones": [
                    {"zone_id": "a", "grid_ready": True, "materialized_cells": 0},
                    {"zone_id": "b", "grid_ready": True, "materialized_cells": 0},
                ]
            }
            result = MODULE.select_uncovered(catalog, coverage, grids, set(), set())
            ids = [seed["cell_id"] for seed in result["seeds"]]
            self.assertEqual(len(ids), len(set(ids)))

    def test_grid_center_can_fallback_to_cell_envelope(self) -> None:
        grid = {
            "cells": [
                {"bbox": [1000, 2000, 1500, 2500]},
                {"bbox": [1500, 2500, 2000, 3000]},
            ]
        }
        self.assertEqual(MODULE.grid_center(grid), (1500.0, 2500.0))

    def test_reservation_ids_supports_runtime_exclusions_and_flat_lists(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            runtime = root / "runtime.json"
            runtime.write_text(
                json.dumps(
                    {
                        "format": "grand-bruxelles-runtime-exclusions-v1",
                        "excluded_cells": [{"cell_id": "bxl-e1-n1-s500"}],
                    }
                ),
                encoding="utf-8",
            )
            flat = root / "flat.json"
            flat.write_text(
                json.dumps({"reserved_cell_ids": ["bxl-e2-n2-s500", "bad"]}),
                encoding="utf-8",
            )
            self.assertEqual(MODULE.reservation_ids(runtime), {"bxl-e1-n1-s500"})
            self.assertEqual(MODULE.reservation_ids(flat), {"bxl-e2-n2-s500"})


if __name__ == "__main__":
    unittest.main()
