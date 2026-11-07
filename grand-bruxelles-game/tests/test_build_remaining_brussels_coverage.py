from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "build_remaining_brussels_coverage.py"
SPEC = importlib.util.spec_from_file_location("build_remaining_brussels_coverage", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RemainingBrusselsCoverageTests(unittest.TestCase):
    def _write_grid(self, root: Path, zone_id: str, cell_ids: list[str]) -> None:
        root.mkdir(parents=True, exist_ok=True)
        (root / f"{zone_id}.json").write_text(
            json.dumps(
                {
                    "format": "grand-bruxelles-zone-cells-v2",
                    "zone_id": zone_id,
                    "cells": [
                        {"id": cell_id, "bbox": [0.0, 0.0, 500.0, 500.0]}
                        for cell_id in cell_ids
                    ],
                }
            ),
            encoding="utf-8",
        )

    def _write_built_cell(self, root: Path, cell_id: str) -> None:
        cell_dir = root / cell_id
        cell_dir.mkdir(parents=True, exist_ok=True)
        (cell_dir / "manifest.json").write_text(
            json.dumps(
                {
                    "format": "grand-bruxelles-urbis-built-cell-v1",
                    "cell_id": cell_id,
                    "bbox": [0.0, 0.0, 500.0, 500.0],
                    "runtime": {},
                }
            ),
            encoding="utf-8",
        )

    def test_shared_global_cell_is_not_double_counted(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            grids = root / "grids"
            built = root / "built"
            self._write_grid(grids, "a", ["cell-shared", "cell-a"])
            self._write_grid(grids, "b", ["cell-shared", "cell-b"])
            self._write_built_cell(built, "cell-shared")
            self._write_built_cell(built, "cell-a")

            catalog = {
                "zones": [
                    {"id": "a", "name": "A", "wave": "R1", "priority": 1},
                    {"id": "b", "name": "B", "wave": "R1", "priority": 2},
                ]
            }
            report = MODULE.build_report(catalog, grids, built, None)

            self.assertEqual(report["unique_planned_cells_known"], 3)
            self.assertEqual(report["materialized_cells_total"], 2)
            self.assertEqual(report["materialized_cells_in_known_grids"], 2)
            self.assertEqual(report["known_grid_coverage_percent"], 66.67)
            self.assertEqual(report["shared_cross_municipality_cell_count"], 1)
            self.assertEqual(report["shared_cross_municipality_cells"]["cell-shared"], ["a", "b"])
            self.assertEqual(report["zones"][0]["coverage_percent"], 100.0)
            self.assertEqual(report["zones"][1]["coverage_percent"], 50.0)

    def test_missing_grid_is_reported_without_guessing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            report = MODULE.build_report(
                {"zones": [{"id": "missing", "name": "Missing", "priority": 1}]},
                root / "grids",
                root / "built",
                None,
            )
            zone = report["zones"][0]
            self.assertFalse(zone["grid_ready"])
            self.assertEqual(zone["planned_cells"], 0)
            self.assertEqual(zone["coverage_percent"], 0.0)
            self.assertEqual(report["unique_planned_cells_known"], 0)

    def test_runtime_index_metrics_are_included(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            index = root / "runtime_index.json"
            index.write_text(
                json.dumps(
                    {
                        "format": "grand-bruxelles-urbis-runtime-index-v2",
                        "cell_count": 4,
                        "excluded_cell_count": 1,
                        "cells": [],
                    }
                ),
                encoding="utf-8",
            )
            report = MODULE.build_report(
                {"zones": [{"id": "x", "name": "X", "priority": 1}]},
                root / "grids",
                root / "built",
                index,
            )
            self.assertEqual(report["runtime"]["streamable_cells"], 4)
            self.assertEqual(report["runtime"]["excluded_cells"], 1)

    def test_invalid_built_cell_manifest_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            cell_dir = root / "bad"
            cell_dir.mkdir()
            (cell_dir / "manifest.json").write_text(json.dumps({"format": "wrong"}), encoding="utf-8")
            with self.assertRaises(ValueError):
                MODULE.load_materialized_ids(root)


if __name__ == "__main__":
    unittest.main()
