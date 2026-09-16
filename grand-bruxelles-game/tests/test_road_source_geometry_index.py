#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path

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
        assert entry["source_path"].startswith("data/osm/")
        assert entry["source_path"].endswith(".game.json")
        source_path = ROOT / entry["source_path"]
        assert entry["source_sha256"] == hashlib.sha256(source_path.read_bytes()).hexdigest()
        assert len(entry["geometry_sha256"]) == 64
        assert entry["point_count"] >= 2
        assert len(entry["bbox"]) == 4
        min_x, min_z, max_x, max_z = entry["bbox"]
        assert min_x <= max_x and min_z <= max_z


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
