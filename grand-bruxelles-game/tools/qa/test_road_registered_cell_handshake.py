#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path

from road_registered_cell_handshake import validate_handshake


def write(path: Path, payload):
    path.write_text(json.dumps(payload))


class RoadRegisteredCellHandshakeTest(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.root = Path(self.td.name)
        self.road = self.root / "road.json"
        self.cells = self.root / "cells.json"
        self.crosswalk = self.root / "crosswalk.json"
        write(self.road, {
            "format": "grand-bruxelles-road-runtime-index-v1",
            "source_lookup_only": True,
            "authorization": {
                "source_lookup_only": True,
                "collision_authorized": False,
                "jouable_authorized": False,
                "render_authorized": False,
                "runtime_mount_authorized": False,
                "safe_spawn_authorized": False,
            },
            "documents": [{"path": "data/osm/vertical_slice_01.game.json", "sha256": "a" * 64, "road_ids": [100, 200]}],
        })
        write(self.cells, {
            "schema": "grand-bruxelles-registered-cell-manifest-index-v1",
            "destination_readiness": "REGISTERED_CELL_INDEX_EVIDENCE_ONLY",
            "registered_cell_count": 1,
            "entries": [{
                "cell_id": "bxl-e149000-n169000-s500",
                "evidence_only": True,
                "runtime_mount_authorized": False,
                "rendered_geometry_authorized": False,
                "collision_authorized": False,
                "safe_spawn_authorized": False,
                "jouable_promotion_authorized": False,
            }],
            "runtime_directory_scan_authorized": False,
            "road_crosswalk_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        })

    def tearDown(self):
        self.td.cleanup()

    def payload(self):
        return {
            "schema": "grand-bruxelles-road-registered-cell-crosswalk-v1",
            "destination_readiness": "ROAD_CELL_CROSSWALK_EVIDENCE_ONLY",
            "rows": [{
                "road_osm_id": 100,
                "cell_id": "bxl-e149000-n169000-s500",
                "mapping_evidence_only": True,
                "runtime_mount_authorized": False,
                "rendered_geometry_authorized": False,
                "collision_authorized": False,
                "safe_spawn_authorized": False,
                "jouable_promotion_authorized": False,
            }],
            "runtime_directory_scan_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        }

    def test_valid_mapping_is_evidence_only(self):
        write(self.crosswalk, self.payload())
        result = validate_handshake(self.road, self.cells, self.crosswalk)
        self.assertEqual(result["mapped_road_count"], 1)
        self.assertFalse(result["runtime_authorized"])

    def test_unknown_road_fails_closed(self):
        payload = self.payload(); payload["rows"][0]["road_osm_id"] = 999
        write(self.crosswalk, payload)
        with self.assertRaises(RuntimeError):
            validate_handshake(self.road, self.cells, self.crosswalk)

    def test_unknown_cell_fails_closed(self):
        payload = self.payload(); payload["rows"][0]["cell_id"] = "bxl-e0-n0-s500"
        write(self.crosswalk, payload)
        with self.assertRaises(RuntimeError):
            validate_handshake(self.road, self.cells, self.crosswalk)

    def test_duplicate_road_mapping_fails_closed(self):
        payload = self.payload(); payload["rows"].append(dict(payload["rows"][0]))
        write(self.crosswalk, payload)
        with self.assertRaises(RuntimeError):
            validate_handshake(self.road, self.cells, self.crosswalk)

    def test_runtime_authorization_fails_closed(self):
        payload = self.payload(); payload["rows"][0]["safe_spawn_authorized"] = True
        write(self.crosswalk, payload)
        with self.assertRaises(RuntimeError):
            validate_handshake(self.road, self.cells, self.crosswalk)

    def test_registered_cell_authorization_fails_closed(self):
        cells = json.loads(self.cells.read_text())
        cells["entries"][0]["runtime_mount_authorized"] = True
        write(self.cells, cells)
        write(self.crosswalk, self.payload())
        with self.assertRaises(RuntimeError):
            validate_handshake(self.road, self.cells, self.crosswalk)


if __name__ == "__main__":
    unittest.main()
