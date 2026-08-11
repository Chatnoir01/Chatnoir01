import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "select_zone_seed_cell.py"
SPEC = importlib.util.spec_from_file_location("select_zone_seed_cell", TOOL)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class ZoneSeedSelectionTests(unittest.TestCase):
    def test_distance_is_zero_when_anchor_is_inside_cell(self):
        self.assertEqual(MODULE.distance_point_to_bbox(147750, 169250, [147500, 169000, 148000, 169500]), 0.0)

    def test_select_seed_prefers_cell_touching_anchor(self):
        payload = {
            "format": "grand-bruxelles-zone-cells-v2",
            "zone_id": "anderlecht",
            "cell_count": 3,
            "cells": [
                {"id": "far", "bbox": [143500, 166000, 144000, 166500]},
                {"id": "near", "bbox": [147500, 169000, 148000, 169500]},
                {"id": "east", "bbox": [148000, 169000, 148500, 169500]},
            ],
        }
        selected = MODULE.select_seed(payload, 147868.29422791934, 169538.62414926197)
        self.assertEqual(selected["id"], "near")
        self.assertAlmostEqual(selected["seed_distance_m"], 38.624, places=3)

    def test_one_cell_manifest_records_selection_provenance(self):
        payload = {
            "format": "grand-bruxelles-zone-cells-v2",
            "zone_id": "anderlecht",
            "cell_count": 2,
            "cells": [
                {"id": "a", "bbox": [147000, 169000, 147500, 169500]},
                {"id": "b", "bbox": [147500, 169000, 148000, 169500]},
            ],
        }
        selected = MODULE.select_seed(payload, 147868.0, 169539.0)
        result = MODULE.one_cell_manifest(payload, selected, 147868.0, 169539.0)
        self.assertEqual(result["cell_count"], 1)
        self.assertEqual(len(result["cells"]), 1)
        self.assertEqual(result["seed_selection"]["selected_cell_id"], result["cells"][0]["id"])
        self.assertEqual(result["seed_selection"]["strategy"], "nearest_bbox_to_lambert72_anchor")


if __name__ == "__main__":
    unittest.main()
