#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
VALIDATOR = PROJECT / "tools" / "validate_road_destination_source_lock.py"
LOCK = PROJECT / "data" / "osm" / "road_destination_sources.lock.json"
SOURCE = PROJECT / "data" / "osm" / "vertical_slice_01.game.json"
SOURCE_KEY = "data/osm/vertical_slice_01.game.json"
# Fresh-head rebuild anchor: this regression is intentionally deterministic and network-free.


def _run(lock_path: Path, source_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(VALIDATOR),
            "--source-root",
            str(source_path.parent),
            "--lock",
            str(lock_path),
        ],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=False,
    )


def _expect_rejected(
    lock_doc: dict[str, object],
    source_doc: dict[str, object],
    needle: str,
    *,
    preserve_bad_digest: bool = False,
) -> None:
    with tempfile.TemporaryDirectory(prefix="gb-road-source-lock-") as tmp:
        source_root = Path(tmp) / "data" / "osm"
        source_root.mkdir(parents=True)
        lock_path = source_root / "road_destination_sources.lock.json"
        source_path = source_root / "vertical_slice_01.game.json"

        source_bytes = json.dumps(
            source_doc,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ).encode("utf-8")
        source_path.write_bytes(source_bytes)

        effective_lock = json.loads(json.dumps(lock_doc))
        if not preserve_bad_digest:
            docs = effective_lock["documents"]
            assert isinstance(docs, dict)
            docs[SOURCE_KEY] = hashlib.sha256(source_bytes).hexdigest()
        lock_path.write_text(
            json.dumps(effective_lock, sort_keys=True, allow_nan=False),
            encoding="utf-8",
        )

        result = _run(lock_path, source_path)
        assert result.returncode != 0, result.stdout
        assert needle.lower() in (result.stdout + result.stderr).lower(), result.stderr


def main() -> int:
    lock_doc = json.loads(LOCK.read_text(encoding="utf-8"))
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))

    baseline = _run(LOCK, SOURCE)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
    assert "ROAD_DESTINATION_SOURCE_LOCK_OK" in baseline.stdout

    with tempfile.TemporaryDirectory(prefix="gb-road-source-lock-path-") as tmp:
        tmp_root = Path(tmp)
        source_root = tmp_root / "data" / "osm"
        source_root.mkdir(parents=True)
        source_path = source_root / "vertical_slice_01.game.json"
        source_path.write_bytes(SOURCE.read_bytes())
        external_lock = tmp_root / "external-road-source.lock.json"
        external_lock.write_bytes(LOCK.read_bytes())
        external_result = _run(external_lock, source_path)
        assert external_result.returncode != 0, external_result.stdout
        assert "lock path" in (external_result.stdout + external_result.stderr).lower()

    bad_license = json.loads(json.dumps(lock_doc))
    bad_license["license"] = "UNKNOWN"
    _expect_rejected(bad_license, source_doc, "license")

    bad_digest = json.loads(json.dumps(lock_doc))
    docs = bad_digest["documents"]
    assert isinstance(docs, dict)
    docs[SOURCE_KEY] = "0" * 64
    _expect_rejected(bad_digest, source_doc, "sha256", preserve_bad_digest=True)

    bad_corridor_type = json.loads(json.dumps(source_doc))
    bad_corridor_type["corridor"] = []
    _expect_rejected(lock_doc, bad_corridor_type, "corridor")

    bad_corridor_name = json.loads(json.dumps(source_doc))
    corridor = bad_corridor_name["corridor"]
    assert isinstance(corridor, dict)
    corridor["name"] = " Midi -> Anneessens -> Bourse -> Grand-Place "
    _expect_rejected(lock_doc, bad_corridor_name, "corridor.name")

    bad_anchor_id = json.loads(json.dumps(source_doc))
    corridor = bad_anchor_id["corridor"]
    assert isinstance(corridor, dict)
    anchors = corridor["anchors"]
    assert isinstance(anchors, list) and anchors and isinstance(anchors[0], dict)
    anchors[0]["id"] = " midi "
    _expect_rejected(lock_doc, bad_anchor_id, "anchors[0].id")

    duplicate_anchor_id = json.loads(json.dumps(source_doc))
    corridor = duplicate_anchor_id["corridor"]
    assert isinstance(corridor, dict)
    anchors = corridor["anchors"]
    assert isinstance(anchors, list) and len(anchors) >= 2
    assert isinstance(anchors[0], dict) and isinstance(anchors[1], dict)
    anchors[1]["id"] = anchors[0]["id"]
    _expect_rejected(lock_doc, duplicate_anchor_id, "duplicate")

    bad_anchor_coordinate = json.loads(json.dumps(source_doc))
    corridor = bad_anchor_coordinate["corridor"]
    assert isinstance(corridor, dict)
    anchors = corridor["anchors"]
    assert isinstance(anchors, list) and anchors and isinstance(anchors[0], dict)
    anchors[0]["x"] = "-668.5"
    _expect_rejected(lock_doc, bad_anchor_coordinate, "anchors[0].x")

    bad_selection_radius = json.loads(json.dumps(source_doc))
    corridor = bad_selection_radius["corridor"]
    assert isinstance(corridor, dict)
    selection_radius = corridor["selection_radius_m"]
    assert isinstance(selection_radius, dict)
    selection_radius["roads"] = 0
    _expect_rejected(lock_doc, bad_selection_radius, "selection_radius_m.roads")

    out_of_scope_road = json.loads(json.dumps(source_doc))
    roads = out_of_scope_road["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["points"] = [[100000.0, 100000.0], [100010.0, 100010.0]]
    _expect_rejected(lock_doc, out_of_scope_road, "selection radius")

    bad_stats = json.loads(json.dumps(source_doc))
    stats = bad_stats["stats"]
    assert isinstance(stats, dict)
    stats["roads"] = int(stats["roads"]) + 1
    _expect_rejected(lock_doc, bad_stats, "accounting")

    bad_source_stats = json.loads(json.dumps(source_doc))
    source_stats = bad_source_stats["source_stats"]
    assert isinstance(source_stats, dict)
    source_stats["drivable_roads"] = int(source_stats["roads"]) + 1
    _expect_rejected(lock_doc, bad_source_stats, "source_stats")

    bad_road_id_type = json.loads(json.dumps(source_doc))
    roads = bad_road_id_type["roads"]
    assert isinstance(roads, list) and roads
    assert isinstance(roads[0], dict)
    roads[0]["osm_id"] = str(roads[0]["osm_id"])
    _expect_rejected(lock_doc, bad_road_id_type, "osm_id")

    bad_road_id_zero = json.loads(json.dumps(source_doc))
    roads = bad_road_id_zero["roads"]
    assert isinstance(roads, list) and roads
    assert isinstance(roads[0], dict)
    roads[0]["osm_id"] = 0
    _expect_rejected(lock_doc, bad_road_id_zero, "osm_id")

    duplicate_road_id = json.loads(json.dumps(source_doc))
    roads = duplicate_road_id["roads"]
    assert isinstance(roads, list) and len(roads) >= 2
    assert isinstance(roads[0], dict) and isinstance(roads[1], dict)
    roads[1]["osm_id"] = roads[0]["osm_id"]
    _expect_rejected(lock_doc, duplicate_road_id, "duplicate")

    bad_road_name_type = json.loads(json.dumps(source_doc))
    roads = bad_road_name_type["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["name"] = 123
    _expect_rejected(lock_doc, bad_road_name_type, "name")

    bad_road_name_whitespace = json.loads(json.dumps(source_doc))
    roads = bad_road_name_whitespace["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["name"] = " "
    _expect_rejected(lock_doc, bad_road_name_whitespace, "name")

    bad_road_class_type = json.loads(json.dumps(source_doc))
    roads = bad_road_class_type["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["class"] = ["primary"]
    _expect_rejected(lock_doc, bad_road_class_type, "class")

    bad_road_class_whitespace = json.loads(json.dumps(source_doc))
    roads = bad_road_class_whitespace["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["class"] = " primary "
    _expect_rejected(lock_doc, bad_road_class_whitespace, "class")

    bad_drivable_type = json.loads(json.dumps(source_doc))
    roads = bad_drivable_type["roads"]
    stats = bad_drivable_type["stats"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    assert roads[0].get("drivable") is True
    assert isinstance(stats, dict)
    roads[0]["drivable"] = "true"
    stats["drivable_roads"] = int(stats["drivable_roads"]) - 1
    _expect_rejected(lock_doc, bad_drivable_type, "drivable")

    bad_points_type = json.loads(json.dumps(source_doc))
    roads = bad_points_type["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["points"] = "0,0;1,1"
    _expect_rejected(lock_doc, bad_points_type, "points")

    bad_points_short = json.loads(json.dumps(source_doc))
    roads = bad_points_short["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["points"] = [[0.0, 0.0]]
    _expect_rejected(lock_doc, bad_points_short, "points")

    bad_point_shape = json.loads(json.dumps(source_doc))
    roads = bad_point_shape["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["points"] = [[0.0, 0.0, 1.0], [1.0, 1.0]]
    _expect_rejected(lock_doc, bad_point_shape, "points")

    bad_point_coordinate = json.loads(json.dumps(source_doc))
    roads = bad_point_coordinate["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["points"] = [["0.0", 0.0], [1.0, 1.0]]
    _expect_rejected(lock_doc, bad_point_coordinate, "points")

    degenerate_points = json.loads(json.dumps(source_doc))
    roads = degenerate_points["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["points"] = [[1.0, 1.0], [1.0, 1.0]]
    _expect_rejected(lock_doc, degenerate_points, "distinct")

    bad_width_type = json.loads(json.dumps(source_doc))
    roads = bad_width_type["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["width"] = str(roads[0]["width"])
    _expect_rejected(lock_doc, bad_width_type, "width")

    bad_width_zero = json.loads(json.dumps(source_doc))
    roads = bad_width_zero["roads"]
    assert isinstance(roads, list) and roads and isinstance(roads[0], dict)
    roads[0]["width"] = 0
    _expect_rejected(lock_doc, bad_width_zero, "width")

    print(
        "ROAD_DESTINATION_SOURCE_LOCK_TEST_OK "
        "digest=true provenance=true accounting=true lock_path=true "
        "corridor_selection_integrity=true road_selection_geometry_integrity=true "
        "road_osm_id_integrity=true road_name_class_integrity=true "
        "road_drivable_bool_integrity=true road_geometry_integrity=true "
        "road_width_integrity=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())