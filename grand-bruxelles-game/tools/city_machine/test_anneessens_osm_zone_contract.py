#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"
LEGACY = ROOT / "data/osm/anneessens_environment_points.game.json"
TARGET = ROOT / "data/osm/zones/anneessens/environment.game.json"
EXPECTED_IDS = [4672009403, 4672009414, 4672009415, 4672009416, 4672009417, 11929097332, 11929097333]
EXPECTED_ANCHOR = [-272.04, -217.07]
EXPECTED_RADIUS_M = 130.0


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"expected JSON object: {path}")
    return value


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class AnneessensOsmZoneContractTest(unittest.TestCase):
    def test_standard_zone_contract_preserves_current_runtime_subset(self) -> None:
        self.assertTrue(TARGET.is_file(), f"standard Anneessens OSM zone contract missing: {TARGET}")

        source = load(SOURCE)
        legacy = load(LEGACY)
        target = load(TARGET)

        self.assertEqual(source.get("format"), "grand-bruxelles-osm-v1")
        self.assertEqual(source.get("source"), "OpenStreetMap contributors via Overpass API")
        self.assertEqual(source.get("license"), "ODbL-1.0")
        self.assertEqual(legacy.get("format"), "grand-bruxelles-osm-environment-points-v1")
        self.assertEqual(legacy.get("zone"), "anneessens")

        self.assertEqual(target.get("format"), "grand-bruxelles-osm-zone-environment-v1")
        self.assertEqual(target.get("zone"), "anneessens")
        self.assertEqual(target.get("source"), source.get("source"))
        self.assertEqual(target.get("license"), "ODbL-1.0")
        self.assertEqual(target.get("coordinate_space"), "game_xz_m")

        upstream = target.get("upstream")
        self.assertIsInstance(upstream, dict)
        self.assertEqual(upstream.get("path"), "data/osm/vertical_slice_01.game.json")
        self.assertEqual(upstream.get("sha256"), sha256(SOURCE))
        self.assertEqual(upstream.get("format"), source.get("format"))
        self.assertEqual(upstream.get("origin"), source.get("origin"))

        selection = target.get("selection")
        self.assertIsInstance(selection, dict)
        self.assertEqual(selection.get("policy"), "preserve_existing_runtime_subset_v1")
        self.assertEqual(selection.get("anchor"), EXPECTED_ANCHOR)
        self.assertEqual(float(selection.get("radius_m", -1)), EXPECTED_RADIUS_M)
        self.assertFalse(bool(selection.get("coverage_complete", True)))
        self.assertEqual(sorted(int(v) for v in selection.get("osm_ids", [])), sorted(EXPECTED_IDS))

        source_points = source.get("environment_points")
        self.assertIsInstance(source_points, list)
        source_by_id = {int(row["osm_id"]): row for row in source_points if isinstance(row, dict) and "osm_id" in row}
        self.assertTrue(set(EXPECTED_IDS).issubset(source_by_id), "one or more existing Anneessens OSM ids vanished from upstream slice")

        expected_points = [source_by_id[osm_id] for osm_id in EXPECTED_IDS]
        expected_points.sort(key=lambda row: (str(row.get("kind", "")), int(row.get("osm_id", 0))))

        legacy_points = legacy.get("points")
        self.assertIsInstance(legacy_points, list)
        legacy_points = sorted(legacy_points, key=lambda row: (str(row.get("kind", "")), int(row.get("osm_id", 0))))
        self.assertEqual(legacy_points, expected_points, "legacy Anneessens runtime subset drifted from committed OSM slice")

        target_points = target.get("environment_points")
        self.assertIsInstance(target_points, list)
        self.assertEqual(target_points, expected_points, "standard zone contract must preserve exact current player-visible OSM points")
        self.assertEqual(len({int(row["osm_id"]) for row in target_points}), len(target_points))

        stats = target.get("stats")
        self.assertIsInstance(stats, dict)
        self.assertEqual(stats, {"bollard": 0, "street_lamp": 0, "total": 7, "tree": 7})
        self.assertEqual(legacy.get("radius_m"), EXPECTED_RADIUS_M)


if __name__ == "__main__":
    unittest.main()
