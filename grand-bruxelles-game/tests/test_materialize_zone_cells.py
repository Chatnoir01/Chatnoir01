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
    def test_load_manifest_validates_format(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "manifest.json"
            path.write_text(json.dumps({"format": "wrong", "cells": []}), encoding="utf-8")
            with self.assertRaises(ValueError):
                MODULE.load_manifest(path)

    def test_command_contains_exact_cell_bbox(self) -> None:
        cell = {
            "id": "anderlecht-001-002",
            "bbox": [147500.0, 169500.0, 148000.0, 170000.0],
        }
        command = MODULE.command_for_cell(cell, Path("out"), 3)
        self.assertIn("anderlecht-001-002", command)
        self.assertIn("147500.0,169500.0,148000.0,170000.0", command)
        self.assertIn("3", command)
        self.assertTrue(any("build_urbis_cell.py" in value for value in command))


if __name__ == "__main__":
    unittest.main()
