from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "plan_remaining_brussels_height_tiles.py"
SPEC = importlib.util.spec_from_file_location("plan_remaining_brussels_height_tiles", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RemainingBrusselsHeightTilePlanTests(unittest.TestCase):
    def test_parses_standard_500m_cell(self) -> None:
        self.assertEqual(MODULE.parse_cell_id("bxl-e149500-n169000-s500"), (149500, 169000, 500))

    def test_rejects_non_cell_identifier(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.parse_cell_id("ixelles-centre")

    def test_exact_kilometre_boundary_does_not_pull_adjacent_tile(self) -> None:
        self.assertEqual(
            MODULE.tile_codes_for_bbox(149500, 169000, 150000, 169500),
            ["149169"],
        )

    def test_cell_crossing_kilometre_boundary_requests_both_tiles(self) -> None:
        self.assertEqual(
            MODULE.tile_codes_for_bbox(149750, 169000, 150250, 169500),
            ["149169", "150169"],
        )

    def test_current_five_ixelles_cells_require_minimal_two_tiles(self) -> None:
        cells = [
            "bxl-e149000-n169000-s500",
            "bxl-e149000-n169500-s500",
            "bxl-e149500-n168500-s500",
            "bxl-e149500-n169000-s500",
            "bxl-e149500-n169500-s500",
        ]
        self.assertEqual(MODULE.tile_codes_for_cells(cells), ["149168", "149169"])
        plan = MODULE.build_plan(cells)
        self.assertEqual(plan["bbox_epsg31370"], [149000, 168500, 150000, 170000])
        self.assertEqual(plan["expected_1km_tile_codes"], ["149168", "149169"])
        self.assertEqual(plan["source_crs"], "EPSG:31370")
        self.assertIn("DSM", plan["height_method_target"])
        self.assertIn("DTM", plan["height_method_target"])

    def test_official_dataset_ids_are_pinned(self) -> None:
        plan = MODULE.build_plan(["bxl-e149500-n169000-s500"])
        self.assertEqual(plan["official_sources"]["dsm"]["dataset_id"], "8c2d921e-6a53-11ed-bfb5-010101010000")
        self.assertEqual(plan["official_sources"]["dtm"]["dataset_id"], "1d7bd49d-fe83-4388-af85-6f5dc8ec7909")


if __name__ == "__main__":
    unittest.main()
