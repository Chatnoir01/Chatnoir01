from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "build_brussels_city_remaining_coverage.py"
SPEC = importlib.util.spec_from_file_location("build_brussels_city_remaining_coverage", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BrusselsCityRemainingCoverageTests(unittest.TestCase):
    def _grid(self, root: Path, filename: str, ids: list[str]) -> None:
        root.mkdir(parents=True, exist_ok=True)
        (root / filename).write_text(json.dumps({
            "format": "grand-bruxelles-zone-cells-v2",
            "cell_count": len(ids),
            "cells": [{"id": cell_id, "bbox": [0, 0, 500, 500]} for cell_id in ids],
        }), encoding="utf-8")

    def _built(self, root: Path, cell_id: str) -> None:
        path = root / cell_id
        path.mkdir(parents=True, exist_ok=True)
        (path / "manifest.json").write_text(json.dumps({
            "format": "grand-bruxelles-urbis-built-cell-v1",
            "cell_id": cell_id,
            "bbox": [0, 0, 500, 500],
        }), encoding="utf-8")

    def test_shared_cells_are_counted_once_globally(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            grids = root / "grids"
            built = root / "built"
            definitions = list(MODULE.PRODUCTION_SUBZONES)
            for _, _, filename in definitions:
                self._grid(grids, filename, [])
            self._grid(grids, definitions[0][2], ["bxl-e1-n1-s500", "bxl-e2-n2-s500"])
            self._grid(grids, definitions[1][2], ["bxl-e2-n2-s500", "bxl-e3-n3-s500"])
            self._grid(grids, MODULE.RESERVATION_GRID[2], ["bxl-e9-n9-s500"])
            self._built(built, "bxl-e2-n2-s500")
            report = MODULE.build_report(grids, built, None)
            self.assertEqual(report["unique_planned_production_cells"], 3)
            self.assertEqual(report["materialized_production_cells"], 1)
            self.assertEqual(report["cross_subzone_shared_cell_count"], 1)
            self.assertEqual(report["cross_subzone_shared_cells"]["bxl-e2-n2-s500"], ["haren", "neder-over-heembeek"])

    def test_laeken_is_reservation_only_and_never_counts_as_production(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            grids = root / "grids"
            built = root / "built"
            for _, _, filename in MODULE.PRODUCTION_SUBZONES:
                self._grid(grids, filename, [])
            self._grid(grids, MODULE.RESERVATION_GRID[2], ["bxl-e9-n9-s500"])
            self._built(built, "bxl-e9-n9-s500")
            report = MODULE.build_report(grids, built, None)
            self.assertEqual(report["materialized_production_cells"], 0)
            self.assertEqual(report["reservation_only"]["reserved_cells"], 1)
            self.assertEqual(report["reservation_only"]["materialized_by_this_branch"], ["bxl-e9-n9-s500"])
            self.assertIn("pentagon-outside-main-corridor", report["known_remaining_scope"]["still_requires_separate_polygon_or_ownership_difference"])

    def test_missing_production_grid_is_reported_not_guessed(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            report = MODULE.build_report(Path(temp_dir) / "grids", Path(temp_dir) / "built", None)
            self.assertEqual(report["production_subzone_grids_ready"], 0)
            self.assertEqual(report["production_subzones_with_materialized_cell"], 0)
            self.assertTrue(all(not item["grid_ready"] for item in report["subzones"]))


if __name__ == "__main__":
    unittest.main()
