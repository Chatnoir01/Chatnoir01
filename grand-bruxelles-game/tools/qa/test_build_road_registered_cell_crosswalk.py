#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path

from build_road_registered_cell_crosswalk import build_crosswalk


class BuildRoadRegisteredCellCrosswalkTest(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.root = Path(self.td.name)
        self.coverage = self.root / "coverage.json"
        self.cells = self.root / "cells.json"
        self.road_index = self.root / "roads.json"
        self.coverage.write_text(json.dumps({
            "schema": "grand-bruxelles-road-cell-coverage-candidates-v2",
            "status": "DISCOVERED_SOURCE_ONLY",
            "road_semantic_sha256": "a" * 64,
            "semantic_sha256": "b" * 64,
            "candidates": [
                {"grid_cell_id": "E147500_N170000", "bbox": [147500.0,170000.0,148000.0,170500.0], "road_ids": [10,20]},
                {"grid_cell_id": "E147500_N169500", "bbox": [147500.0,169500.0,148000.0,170000.0], "road_ids": [20]},
                {"grid_cell_id": "E148000_N170000", "bbox": [148000.0,170000.0,148500.0,170500.0], "road_ids": [30]},
            ],
            "road_cell_mapping_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        }))
        self.cells.write_text(json.dumps({
            "schema": "grand-bruxelles-registered-cell-manifest-index-v1",
            "destination_readiness": "REGISTERED_CELL_INDEX_EVIDENCE_ONLY",
            "registered_cell_count": 2,
            "entries": [
                {"cell_id":"bxl-e147500-n170000-s500","bbox":[147500.0,170000.0,148000.0,170500.0],"evidence_only":True},
                {"cell_id":"bxl-e148000-n170000-s500","bbox":[148000.0,170000.0,148500.0,170500.0],"evidence_only":True},
            ],
            "road_crosswalk_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        }))
        self.road_index.write_text(json.dumps({
            "format":"grand-bruxelles-road-runtime-index-v1",
            "source_lookup_only":True,
            "authorization":{"source_lookup_only":True,"collision_authorized":False,"jouable_authorized":False,"render_authorized":False,"runtime_mount_authorized":False,"safe_spawn_authorized":False},
            "documents":[{"sha256":"c"*64,"road_ids":[10,20,30]}],
        }))

    def tearDown(self):
        self.td.cleanup()

    def test_unique_spatial_cell_roads_only(self):
        result = build_crosswalk(self.coverage, self.cells, self.road_index)
        self.assertEqual([r["road_osm_id"] for r in result["rows"]], [10, 30])
        self.assertEqual(result["excluded_multicell_road_ids"], [20])
        self.assertEqual(result["mapped_road_count"], 2)
        self.assertEqual(result["mapped_cell_count"], 2)
        self.assertFalse(result["road_cell_mapping_authorized"])
        self.assertFalse(result["runtime_mount_authorized"])
        self.assertFalse(result["jouable_promotion_authorized"])

    def test_unknown_runtime_road_fails_closed(self):
        roads = json.loads(self.road_index.read_text())
        roads["documents"][0]["road_ids"] = [10, 20]
        self.road_index.write_text(json.dumps(roads))
        with self.assertRaises(RuntimeError):
            build_crosswalk(self.coverage, self.cells, self.road_index)

    def test_open_authorization_fails_closed(self):
        coverage = json.loads(self.coverage.read_text())
        coverage["runtime_mount_authorized"] = True
        self.coverage.write_text(json.dumps(coverage))
        with self.assertRaises(RuntimeError):
            build_crosswalk(self.coverage, self.cells, self.road_index)


if __name__ == "__main__":
    unittest.main()
