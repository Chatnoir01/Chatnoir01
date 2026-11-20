import importlib.util
import json
import pathlib
import tempfile
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

    def test_select_seed_prefers_nearest_cell(self):
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

    def test_exclude_containing_anchor_keeps_other_workstream_cell_reserved(self):
        payload = {
            "format": "grand-bruxelles-zone-cells-v2",
            "zone_id": "anderlecht",
            "cell_count": 3,
            "cells": [
                {"id": "reserved-midi", "bbox": [147500, 169500, 148000, 170000]},
                {"id": "cureghem-south", "bbox": [147500, 169000, 148000, 169500]},
                {"id": "far", "bbox": [143500, 166000, 144000, 166500]},
            ],
        }
        selected = MODULE.select_seed(
            payload,
            147868.29422791934,
            169538.62414926197,
            exclude_containing_anchor=True,
        )
        self.assertEqual(selected["id"], "cureghem-south")
        self.assertEqual(selected["excluded_anchor_cell_ids"], ["reserved-midi"])
        self.assertAlmostEqual(selected["seed_distance_m"], 38.624, places=3)

    def test_excluded_existing_cell_forces_real_expansion(self):
        payload = {
            "format": "grand-bruxelles-zone-cells-v2",
            "zone_id": "molenbeek",
            "cell_count": 3,
            "cells": [
                {"id": "already-built", "bbox": [147500, 170000, 148000, 170500]},
                {"id": "next-new", "bbox": [147000, 170000, 147500, 170500]},
                {"id": "far", "bbox": [146500, 171000, 147000, 171500]},
            ],
        }
        selected = MODULE.select_seed(
            payload,
            147800.0,
            169900.0,
            excluded_cell_ids={"already-built"},
        )
        self.assertEqual(selected["id"], "next-new")
        self.assertEqual(selected["excluded_existing_cell_ids"], ["already-built"])

    def test_load_existing_cell_ids_reads_built_cell_manifests(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            cell_dir = root / "bxl-e147000-n169500-s500"
            cell_dir.mkdir()
            (cell_dir / "manifest.json").write_text(
                json.dumps(
                    {
                        "format": MODULE.BUILT_CELL_FORMAT,
                        "cell_id": "bxl-e147000-n169500-s500",
                        "bbox": [147000, 169500, 147500, 170000],
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(
                MODULE.load_existing_cell_ids(root),
                {"bxl-e147000-n169500-s500"},
            )

    def test_one_cell_manifest_records_selection_provenance(self):
        payload = {
            "format": "grand-bruxelles-zone-cells-v2",
            "zone_id": "anderlecht",
            "cell_count": 2,
            "cells": [
                {"id": "reserved", "bbox": [147500, 169500, 148000, 170000]},
                {"id": "a", "bbox": [147500, 169000, 148000, 169500]},
            ],
        }
        selected = MODULE.select_seed(payload, 147868.0, 169539.0, exclude_containing_anchor=True)
        result = MODULE.one_cell_manifest(
            payload,
            selected,
            147868.0,
            169539.0,
            exclude_containing_anchor=True,
        )
        self.assertEqual(result["cell_count"], 1)
        self.assertEqual(len(result["cells"]), 1)
        self.assertEqual(result["seed_selection"]["selected_cell_id"], result["cells"][0]["id"])
        self.assertTrue(result["seed_selection"]["exclude_containing_anchor"])
        self.assertEqual(result["seed_selection"]["excluded_anchor_cell_ids"], ["reserved"])
        self.assertEqual(result["seed_selection"]["excluded_existing_cell_ids"], [])
        self.assertEqual(result["seed_selection"]["strategy"], "nearest_bbox_to_lambert72_anchor")


if __name__ == "__main__":
    unittest.main()