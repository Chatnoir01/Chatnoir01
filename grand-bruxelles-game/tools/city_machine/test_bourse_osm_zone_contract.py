#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import unittest
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"
TARGET = ROOT / "data/osm/zones/bourse/environment.game.json"
SOURCE_LABEL = "OpenStreetMap contributors via Overpass API"
LICENSE = "ODbL-1.0"
SUPPORTED_KINDS = ("tree", "street_lamp", "bollard")
EXPECTED_ANCHOR_ID = "bourse"
EXPECTED_ANCHOR = [81.54, -664.58]
EXPECTED_RADIUS_M = 130.0
EXPECTED_POLICY = "committed_corridor_anchor_radius_view_v1"


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"expected JSON object: {path}")
    return value


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_point(raw: dict[str, Any]) -> dict[str, Any]:
    position = raw.get("position")
    if not isinstance(position, list) or len(position) != 2:
        raise AssertionError(f"invalid environment point position: {raw!r}")
    return {
        "osm_id": int(raw["osm_id"]),
        "kind": str(raw["kind"]),
        "position": [float(position[0]), float(position[1])],
    }


class BourseOsmZoneContractTest(unittest.TestCase):
    def test_standard_zone_contract_matches_committed_corridor_radius(self) -> None:
        self.assertTrue(TARGET.is_file(), f"standard Bourse OSM zone contract missing: {TARGET}")

        source = load(SOURCE)
        target = load(TARGET)
        self.assertEqual(source.get("format"), "grand-bruxelles-osm-v1")
        self.assertEqual(source.get("source"), SOURCE_LABEL)
        self.assertEqual(source.get("license"), LICENSE)

        corridor = source.get("corridor")
        self.assertIsInstance(corridor, dict)
        anchors = corridor.get("anchors")
        self.assertIsInstance(anchors, list)
        matching = [row for row in anchors if isinstance(row, dict) and str(row.get("id", "")) == EXPECTED_ANCHOR_ID]
        self.assertEqual(len(matching), 1, "Bourse corridor anchor missing or duplicated")
        anchor = matching[0]
        self.assertEqual([float(anchor["x"]), float(anchor["z"])], EXPECTED_ANCHOR)
        radii = corridor.get("selection_radius_m")
        self.assertIsInstance(radii, dict)
        self.assertEqual(float(radii.get("environment_points", -1)), EXPECTED_RADIUS_M)

        self.assertEqual(target.get("format"), "grand-bruxelles-osm-zone-environment-v1")
        self.assertEqual(target.get("zone"), EXPECTED_ANCHOR_ID)
        self.assertEqual(target.get("source"), SOURCE_LABEL)
        self.assertEqual(target.get("license"), LICENSE)
        self.assertEqual(target.get("coordinate_space"), "game_xz_m")

        upstream = target.get("upstream")
        self.assertIsInstance(upstream, dict)
        self.assertEqual(upstream.get("path"), "data/osm/vertical_slice_01.game.json")
        self.assertEqual(upstream.get("sha256"), sha256(SOURCE))
        self.assertEqual(upstream.get("format"), source.get("format"))
        self.assertEqual(upstream.get("origin"), source.get("origin"))

        selection = target.get("selection")
        self.assertIsInstance(selection, dict)
        self.assertEqual(selection.get("policy"), EXPECTED_POLICY)
        self.assertEqual(selection.get("anchor_id"), EXPECTED_ANCHOR_ID)
        self.assertEqual(selection.get("anchor"), EXPECTED_ANCHOR)
        self.assertEqual(float(selection.get("radius_m", -1)), EXPECTED_RADIUS_M)
        self.assertFalse(bool(selection.get("coverage_complete", True)))

        source_points = source.get("environment_points")
        self.assertIsInstance(source_points, list)
        expected: list[dict[str, Any]] = []
        seen_source_ids: set[int] = set()
        for raw in source_points:
            if not isinstance(raw, dict):
                continue
            point = canonical_point(raw)
            self.assertIn(point["kind"], SUPPORTED_KINDS)
            osm_id = int(point["osm_id"])
            self.assertNotIn(osm_id, seen_source_ids, f"duplicate upstream OSM id: {osm_id}")
            seen_source_ids.add(osm_id)
            x, z = map(float, point["position"])
            if math.hypot(x - EXPECTED_ANCHOR[0], z - EXPECTED_ANCHOR[1]) <= EXPECTED_RADIUS_M + 1e-9:
                expected.append(point)
        expected.sort(key=lambda row: (str(row["kind"]), int(row["osm_id"])))
        self.assertGreater(len(expected), 0, "committed corridor slice has no Bourse environment points")

        target_points_raw = target.get("environment_points")
        self.assertIsInstance(target_points_raw, list)
        target_points = [canonical_point(row) for row in target_points_raw if isinstance(row, dict)]
        self.assertEqual(target_points, expected, "Bourse zone view must equal the full supported committed-slice radius subset")
        self.assertEqual(len({int(row["osm_id"]) for row in target_points}), len(target_points))

        counts = Counter(str(row["kind"]) for row in expected)
        expected_stats = {kind: int(counts.get(kind, 0)) for kind in SUPPORTED_KINDS}
        expected_stats["total"] = len(expected)
        self.assertEqual(target.get("stats"), expected_stats)
        self.assertGreater(expected_stats["tree"], 0)
        self.assertGreater(expected_stats["bollard"], 0)


if __name__ == "__main__":
    unittest.main()
