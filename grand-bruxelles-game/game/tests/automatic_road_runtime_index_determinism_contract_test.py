#!/usr/bin/env python3
"""Fail-closed contract for the automatic road destination runtime index.

The runtime index is source-lookup evidence only. It must remain deterministic,
byte-linked to its source documents, globally unambiguous by OSM road id, and
must never imply render/mount/collision/spawn/JOUABLE authorization.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parents[2]
INDEX_PATH = PROJECT_ROOT / "data/runtime/road_destination_runtime_index.json"
HEX = set("0123456789abcdef")


def fail(message: str) -> None:
    raise AssertionError(message)


def exact_sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(ch not in HEX for ch in value):
        fail(f"{label} must be a lowercase 64-hex sha256")
    return value


def load_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"{label} unreadable/invalid JSON: {exc}")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def main() -> None:
    index = load_object(INDEX_PATH, "runtime index")
    if index.get("format") != "grand-bruxelles-road-runtime-index-v1":
        fail("runtime index format drifted")
    if index.get("source_lookup_only") is not True:
        fail("runtime index must remain source_lookup_only=true")

    auth = index.get("authorization")
    if not isinstance(auth, dict):
        fail("authorization must be an object")
    expected_auth = {
        "source_lookup_only": True,
        "runtime_mount_authorized": False,
        "render_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_authorized": False,
    }
    if auth != expected_auth:
        fail(f"authorization rails drifted: {auth!r}")

    exact_sha256(index.get("catalog_sha256"), "catalog_sha256")
    documents = index.get("documents")
    if not isinstance(documents, list) or not documents:
        fail("documents must be a non-empty array")

    paths: list[str] = []
    global_ids: set[int] = set()
    total_ids = 0

    for doc_index, entry in enumerate(documents):
        if not isinstance(entry, dict):
            fail(f"documents[{doc_index}] must be an object")
        path_value = entry.get("path")
        if not isinstance(path_value, str) or not path_value or path_value.startswith("/") or ".." in Path(path_value).parts:
            fail(f"documents[{doc_index}].path must be a normalized project-relative path")
        paths.append(path_value)

        source_path = PROJECT_ROOT / path_value
        if not source_path.is_file():
            fail(f"indexed source document missing: {path_value}")
        expected_digest = exact_sha256(entry.get("sha256"), f"documents[{doc_index}].sha256")
        actual_digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
        if actual_digest != expected_digest:
            fail(f"indexed source digest mismatch for {path_value}: {actual_digest} != {expected_digest}")

        source = load_object(source_path, path_value)
        roads = source.get("roads")
        if not isinstance(roads, list):
            fail(f"{path_value}.roads must be an array")
        source_ids: list[int] = []
        for road_index, road in enumerate(roads):
            if not isinstance(road, dict):
                fail(f"{path_value}.roads[{road_index}] must be an object")
            osm_id = road.get("osm_id")
            if isinstance(osm_id, bool) or not isinstance(osm_id, int) or osm_id <= 0:
                fail(f"{path_value}.roads[{road_index}].osm_id must be a positive JSON integer")
            source_ids.append(osm_id)
        if len(source_ids) != len(set(source_ids)):
            fail(f"{path_value} contains duplicate road osm_id values")

        indexed_ids = entry.get("road_ids")
        if not isinstance(indexed_ids, list) or not indexed_ids:
            fail(f"documents[{doc_index}].road_ids must be a non-empty array")
        for value in indexed_ids:
            if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
                fail(f"documents[{doc_index}].road_ids must contain positive JSON integers only")
        if indexed_ids != sorted(indexed_ids):
            fail(f"documents[{doc_index}].road_ids must be strictly deterministic ascending order")
        if len(indexed_ids) != len(set(indexed_ids)):
            fail(f"documents[{doc_index}].road_ids contains duplicates")
        if set(indexed_ids) != set(source_ids):
            missing = sorted(set(source_ids) - set(indexed_ids))[:8]
            extra = sorted(set(indexed_ids) - set(source_ids))[:8]
            fail(f"runtime index/source road identity mismatch for {path_value}: missing={missing} extra={extra}")
        overlap = global_ids.intersection(indexed_ids)
        if overlap:
            fail(f"road ids resolve to multiple source documents: {sorted(overlap)[:8]}")
        global_ids.update(indexed_ids)
        total_ids += len(indexed_ids)

    if paths != sorted(paths):
        fail("documents must be deterministic lexicographic path order")
    if len(paths) != len(set(paths)):
        fail("documents contains duplicate paths")

    print(
        "AUTOMATIC_ROAD_RUNTIME_INDEX_DETERMINISM_OK: "
        f"documents={len(documents)} roads={total_ids} global_unique=true "
        "source_digest_bound=true source_lookup_only=true downstream_authorized=false"
    )


if __name__ == "__main__":
    main()
