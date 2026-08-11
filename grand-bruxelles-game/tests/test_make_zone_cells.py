from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "make_zone_cells.py"
SPEC = importlib.util.spec_from_file_location("make_zone_cells", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MakeZoneCellsTests(unittest.TestCase):
    def test_collect_positions_feature_collection(self) -> None:
        payload = {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "properties": {},
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [
                            [
                                [147901, 169901],
                                [148101, 169901],
                                [148101, 170101],
                                [147901, 170101],
                                [147901, 169901],
                            ]
                        ],
                    },
                }
            ],
        }
        positions = MODULE.collect_positions(payload)
        self.assertEqual(len(positions), 5)
        self.assertIn((147901.0, 169901.0), positions)
        self.assertIn((148101.0, 170101.0), positions)

    def test_grid_aligns_to_500_m_lambert72(self) -> None:
        cells = MODULE.build_cells(
            147901.0,
            169901.0,
            148101.0,
            170101.0,
            500.0,
            "test-zone",
        )
        self.assertEqual(len(cells), 4)
        self.assertEqual(
            cells[0]["bbox"],
            [147500.0, 169500.0, 148000.0, 170000.0],
        )
        self.assertEqual(
            cells[-1]["bbox"],
            [148000.0, 170000.0, 148500.0, 170500.0],
        )
        self.assertEqual(cells[0]["id"], "test-zone-000-000")
        self.assertIn("fetch_urbis_wfs_bbox.py", cells[0]["fetch_command"])

    def test_empty_geometry_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.collect_positions({"type": "FeatureCollection", "features": []})


if __name__ == "__main__":
    unittest.main()
