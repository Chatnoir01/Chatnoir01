#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import math
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "build_road_source_geometry_index.py"
_spec = importlib.util.spec_from_file_location("road_source_geometry_index", SCRIPT)
assert _spec is not None and _spec.loader is not None
module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(module)


def test_locked_geometry_index_is_deterministic_and_source_only() -> None:
    source_root = ROOT / "data" / "osm"
    first = module.build_index(source_root)
    second = module.build_index(source_root)
    catalog = module._catalog.build_catalog(source_root)
    assert first == second
    assert first["format"] == "grand-bruxelles-road-source-geometry-index-v1"
    assert first["entry_count"] == len(first["entries"]) > 0
    assert first["authorization"] == {
        "source_lookup_only": True,
        "render_authorized": False,
        "collision_authorized": False,
        "runtime_mount_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_authorized": False,
    }
    for key, entry in first["entries"].items():
        assert key == str(entry["osm_id"])
        expected = catalog["entries"][key]
        assert entry["name"] == expected["name"]
        assert entry["class"] == expected["class"]
        assert entry["width"] == expected["width"]
        assert entry["drivable"] is True
        assert entry["source_path"] in expected["source_paths"]
        assert entry["source_path"].startswith("data/osm/")
        assert entry["source_path"].endswith(".game.json")
        source_path = ROOT / entry["source_path"]
        assert entry["source_sha256"] == hashlib.sha256(source_path.read_bytes()).hexdigest()
        assert len(entry["geometry_sha256"]) == 64
        assert entry["point_count"] >= 2
        assert len(entry["bbox"]) == 4
        min_x, min_z, max_x, max_z = entry["bbox"]
        assert min_x <= max_x and min_z <= max_z
        assert type(entry["centerline_length_m"]) is float
        assert math.isfinite(entry["centerline_length_m"])
        assert entry["centerline_length_m"] > 0.0


def test_centerline_length_is_exact_geometry_derived() -> None:
    points = [[0.0, 0.0], [3.0, 4.0], [3.0, 8.0]]
    assert module.centerline_length_m(points) == 9.0


def test_centerline_length_rejects_degenerate_and_overflow_geometry() -> None:
    invalid = (
        [[1.0, 2.0], [1.0, 2.0]],
        [[0.0, 0.0], [1e308, 1e308], [-1e308, -1e308]],
    )
    for points in invalid:
        with pytest.raises(SystemExit, match="ROAD_SOURCE_GEOMETRY_INDEX_FAIL: road centerline has no positive finite source length"):
            module.centerline_length_m(points)


def test_centerline_length_rejects_zero_length_segment_inside_valid_geometry() -> None:
    points = [[0.0, 0.0], [3.0, 4.0], [3.0, 4.0], [3.0, 8.0]]
    with pytest.raises(SystemExit, match="ROAD_SOURCE_GEOMETRY_INDEX_FAIL: road centerline contains zero-length segment index=1"):
        module.centerline_length_m(points)


def test_serialization_is_byte_deterministic(tmp_path: Path) -> None:
    payload = module.build_index(ROOT / "data" / "osm")
    expected = module.serialize_index(payload)
    assert expected.endswith(b"\n")
    assert b"\r\n" not in expected
    first = tmp_path / "a.json"
    second = tmp_path / "b.json"
    first.write_bytes(expected)
    second.write_bytes(module.serialize_index(payload))
    assert first.read_bytes() == second.read_bytes() == expected
