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
        self.assertEqual(len(positions), 4)
        self.assertIn((147901.0, 169901.0), positions)
        self.assertIn((148101.0, 170101.0), positions)

    def test_grid_aligns_to_500_m_lambert72_and_uses_global_id(self) -> None:
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
        self.assertEqual(cells[0]["id"], "bxl-e147500-n169500-s500")
        self.assertEqual(cells[0]["zone_id"], "test-zone")
        self.assertIn("build_urbis_cell.py", cells[0]["fetch_command"])

    def test_same_square_has_same_id_for_two_municipalities(self) -> None:
        first = MODULE.build_cells(147501, 169501, 147999, 169999, 500.0, "anderlecht")
        second = MODULE.build_cells(147501, 169501, 147999, 169999, 500.0, "molenbeek")
        self.assertEqual(first[0]["id"], second[0]["id"])
        self.assertNotEqual(first[0]["zone_id"], second[0]["zone_id"])

    def test_concave_boundary_filters_envelope_only_cell(self) -> None:
        polygon = [[
            (147510.0, 169510.0),
            (148490.0, 169510.0),
            (148490.0, 169990.0),
            (147990.0, 169990.0),
            (147990.0, 170490.0),
            (147510.0, 170490.0),
        ]]
        cells = MODULE.build_cells(
            147510.0,
            169510.0,
            148490.0,
            170490.0,
            500.0,
            "l-zone",
            [polygon],
        )
        ids = {cell["id"] for cell in cells}
        self.assertEqual(len(cells), 3)
        self.assertNotIn("bxl-e148000-n170000-s500", ids)
        self.assertIn("bxl-e147500-n169500-s500", ids)
        self.assertIn("bxl-e148000-n169500-s500", ids)
        self.assertIn("bxl-e147500-n170000-s500", ids)

    def test_hole_does_not_materialize_cell_fully_inside_hole(self) -> None:
        outer = [
            (147000.0, 169000.0),
            (149000.0, 169000.0),
            (149000.0, 171000.0),
            (147000.0, 171000.0),
        ]
        hole = [
            (147400.0, 169400.0),
            (148600.0, 169400.0),
            (148600.0, 170600.0),
            (147400.0, 170600.0),
        ]
        self.assertFalse(
            MODULE.cell_intersects_polygon(
                (147500.0, 169500.0, 148000.0, 170000.0),
                [outer, hole],
            )
        )

    def test_empty_geometry_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.collect_positions({"type": "FeatureCollection", "features": []})


if __name__ == "__main__":
    unittest.main()
