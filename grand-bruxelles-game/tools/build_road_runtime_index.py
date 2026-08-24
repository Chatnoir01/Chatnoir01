#!/usr/bin/env python3
"""Build the deterministic runtime OSM road-source index from the source catalog.

The runtime index is source lookup metadata only. It MUST NOT authorize render,
collision, runtime mounting, safe spawn, or JOUABLE promotion.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-road-runtime-index-v1"
TOOLS_DIR = Path(__file__).resolve().parent
CATALOG_SCRIPT = TOOLS_DIR / "build_road_destination_catalog.py"

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
        if not isinstance(raw_entry, dict):
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: malformed catalog entry {raw_osm_id!r}")
        try:
            osm_id = int(raw_osm_id)
        except (TypeError, ValueError) as exc:
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: invalid OSM id {raw_osm_id!r}") from exc
        if osm_id <= 0 or osm_id in seen_road_ids:
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: duplicate/invalid OSM id {osm_id}")
        seen_road_ids.add(osm_id)

        source_paths = raw_entry.get("source_paths")
        if not isinstance(source_paths, list) or len(source_paths) != 1:
            raise SystemExit(
                "ROAD_RUNTIME_INDEX_FAIL: eligible road must resolve to exactly one runtime source document: "
                f"osm_id={osm_id} source_paths={source_paths!r}"
            )
        source_path = str(source_paths[0]).strip()
        if not source_path.startswith("data/osm/") or not source_path.endswith(".game.json"):
            raise SystemExit(
                f"ROAD_RUNTIME_INDEX_FAIL: source path outside data/osm runtime contract: {source_path!r}"
            )
        road_ids_by_path.setdefault(source_path, []).append(osm_id)

    documents: list[dict[str, Any]] = []
    for source_path in sorted(road_ids_by_path):
        source_sha = str(source_digests.get(source_path, "")).strip().lower()
        if len(source_sha) != 64 or any(ch not in "0123456789abcdef" for ch in source_sha):
            raise SystemExit(
                f"ROAD_RUNTIME_INDEX_FAIL: invalid/missing SHA256 for runtime source {source_path!r}"
            )
        documents.append(
            {
                "path": source_path,
                "road_ids": sorted(road_ids_by_path[source_path]),
                "sha256": source_sha,
            }
        )

    payload: dict[str, Any] = {
        "authorization": dict(AUTHORIZATION),
        "catalog_sha256": str(catalog.get("catalog_sha256", "")).strip().lower(),
        "documents": documents,
        "format": FORMAT,
        "source_lookup_only": True,
    }
    validate_contract(payload)
    return payload


def validate_contract(index: dict[str, Any]) -> None:
    if index.get("format") != FORMAT:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: format drift")
    if index.get("source_lookup_only") is not True:
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: source_lookup_only missing")

    catalog_sha = str(index.get("catalog_sha256", "")).strip().lower()
    if len(catalog_sha) != 64 or any(ch not in "0123456789abcdef" for ch in catalog_sha):
        raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: catalog SHA256 invalid")

    authorization = index.get("authorization")
    if not isinstance(authorization, dict) or authorization.get("source_lookup_only") is not True:
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
    for descriptor in documents:
        if not isinstance(descriptor, dict):
            raise SystemExit("ROAD_RUNTIME_INDEX_FAIL: malformed source descriptor")
        source_path = str(descriptor.get("path", "")).strip()
        source_sha = str(descriptor.get("sha256", "")).strip().lower()
        road_ids = descriptor.get("road_ids")
        if source_path in seen_paths or not source_path.startswith("data/osm/") or not source_path.endswith(".game.json"):
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: duplicate/invalid source path {source_path!r}")
        seen_paths.add(source_path)
        if len(source_sha) != 64 or any(ch not in "0123456789abcdef" for ch in source_sha):
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: invalid SHA256 for {source_path!r}")
        if not isinstance(road_ids, list) or not road_ids:
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: no road ids for {source_path!r}")
        if road_ids != sorted(road_ids):
            raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: road ids are not sorted for {source_path!r}")
        for raw_osm_id in road_ids:
            try:
                osm_id = int(raw_osm_id)
            except (TypeError, ValueError) as exc:
                raise SystemExit(f"ROAD_RUNTIME_INDEX_FAIL: invalid road id {raw_osm_id!r}") from exc
            if osm_id <= 0 or osm_id in seen_road_ids:
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
