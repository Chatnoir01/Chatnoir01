from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "sync_external_branch_reservations.py"
SPEC = importlib.util.spec_from_file_location("sync_external_branch_reservations", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SyncExternalBranchReservationsTests(unittest.TestCase):
    def test_built_and_reserved_grid_cells_are_unioned(self) -> None:
        documents = [
            (
                "built/manifest.json",
                {
                    "format": MODULE.BUILT_FORMAT,
                    "cell_id": "bxl-e147000-n172000-s500",
                },
            ),
            (
                "jette.json",
                {
                    "format": MODULE.GRID_FORMAT,
                    "zone_id": "jette",
                    "cells": [
                        {"id": "bxl-e146500-n173000-s500"},
                        {"id": "bxl-e147000-n172000-s500"},
                    ],
                },
            ),
        ]
        result = MODULE.extract_reservations(documents, {"jette", "laeken"})
        self.assertEqual(result["materialized_cell_ids"], ["bxl-e147000-n172000-s500"])
        self.assertEqual(
            result["planned_cell_ids"],
            ["bxl-e146500-n173000-s500", "bxl-e147000-n172000-s500"],
        )
        self.assertEqual(
            result["reserved_cell_ids"],
            ["bxl-e146500-n173000-s500", "bxl-e147000-n172000-s500"],
        )

    def test_unrelated_grid_zone_is_ignored(self) -> None:
        documents = [
            (
                "other.json",
                {
                    "format": MODULE.GRID_FORMAT,
                    "zone_id": "anderlecht",
                    "cells": [{"id": "bxl-e145500-n169000-s500"}],
                },
            )
        ]
        result = MODULE.extract_reservations(documents, {"jette"})
        self.assertEqual(result["planned_cell_ids"], [])
        self.assertEqual(result["reserved_cell_ids"], [])

    def test_empty_zone_filter_accepts_any_v2_grid(self) -> None:
        documents = [
            (
                "grid.json",
                {
                    "format": MODULE.GRID_FORMAT,
                    "zone_id": "jette",
                    "cells": [{"id": "bxl-e146000-n173000-s500"}],
                },
            )
        ]
        result = MODULE.extract_reservations(documents, set())
        self.assertEqual(result["planned_cell_ids"], ["bxl-e146000-n173000-s500"])

    def test_invalid_cell_ids_are_not_reserved(self) -> None:
        documents = [
            (
                "grid.json",
                {
                    "format": MODULE.GRID_FORMAT,
                    "zone_id": "jette",
                    "cells": [{"id": "jette-000-000"}, {"id": "bxl-e146000-n173000-s500"}],
                },
            ),
            (
                "built.json",
                {"format": MODULE.BUILT_FORMAT, "cell_id": "local-cell"},
            ),
        ]
        result = MODULE.extract_reservations(documents, {"jette"})
        self.assertEqual(result["reserved_cell_ids"], ["bxl-e146000-n173000-s500"])

    def test_valid_global_cell_id_requires_global_scheme(self) -> None:
        self.assertEqual(
            MODULE.valid_global_cell_id("bxl-e147000-n172000-s500"),
            "bxl-e147000-n172000-s500",
        )
        self.assertIsNone(MODULE.valid_global_cell_id("zone-001"))
        self.assertIsNone(MODULE.valid_global_cell_id(""))


if __name__ == "__main__":
    unittest.main()
