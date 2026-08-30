#!/usr/bin/env python3
"""Build the deterministic runtime OSM road-source index from the source catalog.

The runtime index is source lookup metadata only. It MUST NOT authorize render,
collision, runtime mounting, safe spawn, or JOUABLE promotion.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path, PurePosixPath
from typing import Any

FORMAT = "grand-bruxelles-road-runtime-index-v1"
TOOLS_DIR = Path(__file__).resolve().parent
CATALOG_SCRIPT = TOOLS_DIR / "build_road_destination_catalog.py"
INDEX_FIELDS = frozenset({
    "authorization",
    "catalog_sha256",
    "documents",
    "format",
    "source_lookup_only",
})
AUTHORIZATION_FIELDS = frozenset({
    "collision_authorized",
    "jouable_authorized",
    "render_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
    "source_lookup_only",
})
DOCUMENT_FIELDS = frozenset({"path", "road_ids", "sha256"})

_spec = importlib.util.spec_from_file_location("road_destination_catalog", CATALOG_SCRIPT)
if _spec is None or _spec.loader is None:
    raise RuntimeError(f"could not load road destination catalog generator: {CATALOG_SCRIPT}")
_catalog_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_catalog_module)

AUTHORIZATION = {
    "collision_authorized": False,
    "jouable_authorized": False,
    "render_authorized": False,
    "runtime_mount_authorized": False,
    "safe_spawn_authorized": False,
    "source_lookup_only": True,
}


def require_json_string(value: Any, label: str) -> str:
    if type(value) is not str:
        raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: JSON type drift {label}")
    return value


def require_json_int(value: Any, label: str, *, minimum: int | None = None) -> int:
    if type(value) is not int:
        raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: JSON type drift {label}")
    if minimum is not None and value < minimum:
        raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: invalid integer {label}={value}")
    return value


def require_sha256(value: Any, label: str) -> str:
    text = require_json_string(value, label)
    if len(text) != 64 or any(ch not in "0123456789abcdef" for ch in text):
        raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: invalid SHA256 {label}")
    return text


def require_runtime_source_path(value: Any, label: str) -> str:
    source_path = require_json_string(value, label)
    parsed = PurePosixPath(source_path)
    if (
        source_path != source_path.strip()
        or "\\" in source_path
        or parsed.is_absolute()
        or parsed.parts[:2] != ("data", "osm")
        or any(part in ("", ".", "..") for part in parsed.parts)
        or parsed.as_posix() != source_path
        or parsed.suffixes[-2:] != [".game", ".json"]
    ):
        raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: non-canonical source path {source_path!r}")
    return source_path


def build_runtime_index(catalog: dict[str, Any]) -> dict[str, Any]:
    _catalog_module.validate_contract(catalog)

    entries = catalog.get("entries")
    if not isinstance(entries, dict) or not entries:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: catalog contains no eligible road entries")
    source_digests = catalog.get("source_document_sha256")
    if not isinstance(source_digests, dict) or not source_digests:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: catalog source digests missing")

    road_ids_by_path: dict[str, list[int]] = {}
    seen_road_ids: set[int] = set()
    for raw_osm_id, raw_entry in entries.items():
        if type(raw_osm_id) is not str or not raw_osm_id.isdigit():
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: invalid catalog OSM id key {raw_osm_id!r}")
        osm_id = int(raw_osm_id)
        if not isinstance(raw_entry, dict):
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: malformed catalog entry {raw_osm_id!r}")
        if osm_id <= 0 or osm_id in seen_road_ids:
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: duplicate/invalid OSM id {osm_id}")
        seen_road_ids.add(osm_id)

        source_paths = raw_entry.get("source_paths")
        if not isinstance(source_paths, list) or len(source_paths) != 1:
            raise SystemExit(
                "ROAD_RUNTIME_INDEX_FAIL: eligible road must resolve to exactly one runtime source document: "
                f"osm_id={osm_id} source_paths={source_paths!r}"
            )
        source_path = require_runtime_source_path(source_paths[0], f"source path osm_id={osm_id}")
        road_ids_by_path.setdefault(source_path, []).append(osm_id)

    documents: list[dict[str, Any]] = []
    for source_path in sorted(road_ids_by_path):
        source_sha = require_sha256(source_digests.get(source_path), f"runtime source {source_path!r}")
        documents.append(
            {
                "path": source_path,
                "road_ids": sorted(road_ids_by_path[source_path]),
                "sha256": source_sha,
            }
        )

    catalog_sha = require_sha256(catalog.get("catalog_sha256"), "catalog_sha256")
    payload: dict[str, Any] = {
        "authorization": dict(AUTHORIZATION),
        "catalog_sha256": catalog_sha,
        "documents": documents,
        "format": FORMAT,
        "source_lookup_only": True,
    }
    validate_contract(payload)
    return payload


def validate_contract(index: dict[str, Any]) -> None:
    if type(index) is not dict or set(index) != INDEX_FIELDS:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: field set drift")
    if index.get("format") != FORMAT:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: format drift")
    if index.get("source_lookup_only") is not True:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: source_lookup_only missing")

    require_sha256(index.get("catalog_sha256"), "catalog_sha256")

    authorization = index.get("authorization")
    if type(authorization) is not dict or set(authorization) != AUTHORIZATION_FIELDS:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: authorization field set drift")
    if authorization.get("source_lookup_only") is not True:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: source-only authorization rail missing")
    for forbidden in (
        "render_authorized",
        "collision_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
        "jouable_authorized",
    ):
        if authorization.get(forbidden) is not False:
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: {forbidden} must stay false")

    documents = index.get("documents")
    if not isinstance(documents, list) or not documents:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: no runtime source documents")

    seen_paths: set[str] = set()
    seen_road_ids: set[int] = set()
    previous_path: str | None = None
    for descriptor in documents:
        if type(descriptor) is not dict or set(descriptor) != DOCUMENT_FIELDS:
            raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: descriptor field set drift")
        source_path = require_runtime_source_path(descriptor.get("path"), "source path")
        require_sha256(descriptor.get("sha256"), f"source {source_path!r}")
        road_ids = descriptor.get("road_ids")
        if source_path in seen_paths:
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: duplicate/invalid source path {source_path!r}")
        if previous_path is not None and source_path <= previous_path:
            raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: source descriptors are not strictly sorted")
        previous_path = source_path
        seen_paths.add(source_path)
        if not isinstance(road_ids, list) or not road_ids:
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: no road ids for {source_path!r}")
        if road_ids != sorted(road_ids):
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: road ids are not sorted for {source_path!r}")
        for raw_osm_id in road_ids:
            osm_id = require_json_int(raw_osm_id, "road id", minimum=1)
            if osm_id in seen_road_ids:
                raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: duplicate/invalid road id {osm_id}")
            seen_road_ids.add(osm_id)

    if not seen_road_ids:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: runtime road lookup is empty")


def write_index(index: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(index, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path("data/osm"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    catalog = _catalog_module.build_catalog(args.source_root)
    _catalog_module.validate_contract(catalog)
    index = build_runtime_index(catalog)
    write_index(index, args.output)
    road_count = sum(len(document["road_ids"]) for document in index["documents"])
    print(
        "ROAD_RUNTIME_INDEX_OK: "
        f"roads={road_count} documents={len(index['documents'])} "
        f"catalog_sha256={index['catalog_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
