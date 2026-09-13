#!/usr/bin/env python3
import hashlib
import json
import tempfile
from pathlib import Path

from validate_automatic_road_runtime_index_source_identity import ValidationError, validate


def write_fixture(root: Path, *, duplicate_source=False, duplicate_index=False, traversal=False, path_alias=None):
    source_rel = "../outside.json" if traversal else "data/osm/source.json"
    source_path = (root / source_rel).resolve()
    source_path.parent.mkdir(parents=True, exist_ok=True)
    roads = [
        {"osm_id": 101, "name": "A", "drivable": True, "points": [[0, 0], [1, 0]]},
        {"osm_id": 202, "name": "B", "drivable": True, "points": [[1, 0], [2, 0]]},
    ]
    if duplicate_source:
        roads.append({"osm_id": 101, "name": "A duplicate", "drivable": True, "points": [[2, 0], [3, 0]]})
    source_bytes = (json.dumps({"roads": roads, "buildings": []}, sort_keys=True) + "\n").encode()
    source_path.write_bytes(source_bytes)
    road_ids = [101, 202]
    if duplicate_index:
        road_ids.append(101)
    descriptor_path = source_rel if path_alias is None else path_alias
    index = {
        "format": "grand-bruxelles-road-runtime-index-v1",
        "source_lookup_only": True,
        "authorization": {
            "source_lookup_only": True,
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        },
        "documents": [{
            "path": descriptor_path,
            "sha256": hashlib.sha256(source_bytes).hexdigest(),
            "road_ids": road_ids,
        }],
    }
    index_path = root / "data/runtime/index.json"
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(json.dumps(index), encoding="utf-8")
    return index_path


def expect_reject(**kwargs):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        index_path = write_fixture(root, **kwargs)
        try:
            validate(root, index_path)
        except ValidationError:
            return
        raise AssertionError(f"fixture unexpectedly accepted: {kwargs}")


def expect_duplicate_index_key_reject():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        index_path = write_fixture(root)
        raw = index_path.read_text(encoding="utf-8")
        needle = '"source_lookup_only": true'
        assert raw.count(needle) >= 2
        raw = raw.replace(needle, needle + ", " + needle, 1)
        index_path.write_text(raw, encoding="utf-8")
        try:
            validate(root, index_path)
        except ValidationError:
            return
        raise AssertionError("duplicate runtime-index JSON key unexpectedly accepted by semantic identity validator")


def main():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        index_path = write_fixture(root)
        result = validate(root, index_path)
        assert result["indexed_road_count"] == 2
        assert result["source_document_count"] == 1

    expect_reject(duplicate_source=True)
    expect_reject(duplicate_index=True)
    expect_reject(traversal=True)
    expect_reject(path_alias=" data/osm/source.json")
    expect_reject(path_alias="data/osm/source.json ")
    expect_reject(path_alias="res://data/osm/source.json ")
    expect_duplicate_index_key_reject()
    print("AUTOMATIC_ROAD_RUNTIME_INDEX_SOURCE_IDENTITY_REGRESSION_GREEN")


if __name__ == "__main__":
    main()
