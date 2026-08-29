from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "materialize_zone_cells.py"
SPEC = importlib.util.spec_from_file_location("materialize_zone_cells", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MaterializeZoneCellsTests(unittest.TestCase):
    def test_load_manifest_rejects_old_or_unknown_format(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "manifest.json"
            path.write_text(json.dumps({"format": "grand-bruxelles-zone-cells-v1", "cells": []}), encoding="utf-8")
            with self.assertRaises(ValueError):
                MODULE.load_manifest(path)

    def test_valid_manifest_requires_global_ids(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "manifest.json"
            payload = {
                "format": MODULE.CELL_FORMAT,
                "zone_id": "anderlecht",
                "cells": [
                    {
                        "id": "bxl-e147500-n169500-s500",
                        "bbox": [147500.0, 169500.0, 148000.0, 170000.0],
                    }
                ],
            }
            path.write_text(json.dumps(payload), encoding="utf-8")
            loaded = MODULE.load_manifest(path)
            self.assertEqual(loaded["zone_id"], "anderlecht")

    def test_duplicate_global_ids_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "manifest.json"
            cell = {
                "id": "bxl-e147500-n169500-s500",
                "bbox": [147500.0, 169500.0, 148000.0, 170000.0],
            }
            path.write_text(
                json.dumps({"format": MODULE.CELL_FORMAT, "cells": [cell, dict(cell)]}),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                MODULE.load_manifest(path)

    def test_command_contains_exact_cell_bbox(self) -> None:
        cell = {
            "id": "bxl-e147500-n169500-s500",
            "bbox": [147500.0, 169500.0, 148000.0, 170000.0],
        }
        command = MODULE.command_for_cell(cell, Path("out"), 3)
        self.assertIn("bxl-e147500-n169500-s500", command)
        self.assertIn("147500.0,169500.0,148000.0,170000.0", command)
        self.assertIn("3", command)
        self.assertTrue(any("build_urbis_cell.py" in value for value in command))


if __name__ == "__main__":
    unittest.main()
