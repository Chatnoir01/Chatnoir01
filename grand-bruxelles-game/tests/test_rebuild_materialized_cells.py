from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "rebuild_materialized_cells.py"
SPEC = importlib.util.spec_from_file_location("rebuild_materialized_cells", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RebuildMaterializedCellsTests(unittest.TestCase):
    def _write_cell(self, root: Path, cell_id: str, bbox: list[float]) -> None:
        cell_dir = root / cell_id
        cell_dir.mkdir()
        (cell_dir / "manifest.json").write_text(
            json.dumps(
                {
                    "format": MODULE.BUILT_CELL_FORMAT,
                    "cell_id": cell_id,
                    "bbox": bbox,
                    "runtime": {},
                }
            ),
            encoding="utf-8",
        )

    def test_discover_cells_is_sorted_and_uses_manifest_bbox(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self._write_cell(root, "bxl-e147000-n169500-s500", [147000, 169500, 147500, 170000])
            self._write_cell(root, "bxl-e145500-n169000-s500", [145500, 169000, 146000, 169500])
            cells = MODULE.discover_cells(root)
            self.assertEqual(
                [cell["cell_id"] for cell in cells],
                ["bxl-e145500-n169000-s500", "bxl-e147000-n169500-s500"],
            )
            self.assertEqual(cells[0]["bbox"], [145500.0, 169000.0, 146000.0, 169500.0])

    def test_command_rebuilds_same_cell_directory_and_bbox(self) -> None:
        cell = {
            "cell_id": "bxl-e145500-n169000-s500",
            "bbox": [145500.0, 169000.0, 146000.0, 169500.0],
            "output_dir": Path("data/cells/bxl-e145500-n169000-s500"),
        }
        command = MODULE.command_for_cell(cell, 3)
        self.assertIn("bxl-e145500-n169000-s500", command)
        self.assertIn("145500.0,169000.0,146000.0,169500.0", command)
        self.assertIn("data/cells/bxl-e145500-n169000-s500", command)
        self.assertTrue(any("build_urbis_cell.py" in value for value in command))

    def test_invalid_manifest_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "manifest.json"
            path.write_text(json.dumps({"format": "wrong"}), encoding="utf-8")
            with self.assertRaises(ValueError):
                MODULE.load_manifest(path)


if __name__ == "__main__":
    unittest.main()
