#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/city_machine/discover_road_cell_coverage_candidates.py"
spec = importlib.util.spec_from_file_location("road_cell_candidates", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


def fixture() -> dict:
    return {
        "format": "grand-bruxelles-osm-v1", "source": "OpenStreetMap contributors via Overpass API", "license": "ODbL-1.0",
        "stats": {"roads": 2},
        "corridor": {"anchors": [{"id": "a", "name": "A", "x": -100.0, "z": 100.0}, {"id": "b", "name": "B", "x": 600.0, "z": -600.0}]},
        "roads": [
            {"osm_id": 1, "name": "one", "class": "primary", "width": 9.0, "drivable": True, "points": [[-100.0, 100.0], [600.0, -600.0]]},
            {"osm_id": 2, "name": "two", "class": "secondary", "width": 8.0, "drivable": True, "points": [[-90.0, 110.0], [-80.0, 120.0]]},
        ],
        "buildings": [{"osm_id": 99}], "environment_points": [{"osm_id": 100, "kind": "tree"}],
    }


class RoadCellCoverageCandidatesTest(unittest.TestCase):
    def test_discovers_coordinate_cells_without_authorizing_them(self) -> None:
        result = mod.discover_from_payload(fixture(), "a" * 64)
        self.assertEqual(result["schema"], "grand-bruxelles-road-cell-coverage-candidates-v2")
        self.assertEqual(result["status"], "DISCOVERED_SOURCE_ONLY")
        self.assertEqual(result["road_count"], 2)
        self.assertRegex(result["road_semantic_sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(result["road_source_sha256"], "a" * 64)
        self.assertFalse(result["registration_authorized"])
        self.assertFalse(result["road_cell_mapping_authorized"])
        for candidate in result["candidates"]:
            self.assertFalse(candidate["runtime_mount_authorized"])
            self.assertFalse(candidate["jouable_promotion_authorized"])

    def test_unrelated_slice_refresh_does_not_change_road_or_candidate_semantics(self) -> None:
        a = mod.discover_from_payload(fixture(), "a" * 64)
        changed = copy.deepcopy(fixture())
        changed["buildings"].append({"osm_id": 101})
        changed["environment_points"][0]["kind"] = "street_lamp"
        b = mod.discover_from_payload(changed, "b" * 64)
        self.assertNotEqual(a["road_source_sha256"], b["road_source_sha256"])
        self.assertEqual(a["road_semantic_sha256"], b["road_semantic_sha256"])
        self.assertEqual(a["semantic_sha256"], b["semantic_sha256"])

    def test_road_geometry_change_changes_semantic_locks(self) -> None:
        a = mod.discover_from_payload(fixture(), "a" * 64)
        changed = copy.deepcopy(fixture())
        changed["roads"][0]["points"][1][0] += 501.0
        b = mod.discover_from_payload(changed, "b" * 64)
        self.assertNotEqual(a["road_semantic_sha256"], b["road_semantic_sha256"])
        self.assertNotEqual(a["semantic_sha256"], b["semantic_sha256"])

    def test_road_metadata_change_changes_road_semantic_lock(self) -> None:
        a = mod.discover_from_payload(fixture(), "a" * 64)
        changed = copy.deepcopy(fixture())
        changed["roads"][0]["width"] = 12.0
        b = mod.discover_from_payload(changed, "b" * 64)
        self.assertNotEqual(a["road_semantic_sha256"], b["road_semantic_sha256"])

    def test_rejects_duplicate_road_identity(self) -> None:
        payload = fixture(); payload["roads"][1]["osm_id"] = 1
        with self.assertRaisesRegex(ValueError, "unique integers"):
            mod.discover_from_payload(payload, "a" * 64)

    def test_rejects_provider_or_license_drift(self) -> None:
        for key, value in (("source", "other"), ("license", "unknown")):
            payload = fixture(); payload[key] = value
            with self.assertRaises(ValueError):
                mod.discover_from_payload(payload, "a" * 64)

    def test_rejects_duplicate_anchor_identity(self) -> None:
        payload = fixture(); payload["corridor"]["anchors"][1]["id"] = "a"
        with self.assertRaisesRegex(ValueError, "anchor IDs"):
            mod.discover_from_payload(payload, "a" * 64)


if __name__ == "__main__":
    unittest.main()
