#!/usr/bin/env python3
"""Build a deterministic road -> cell mount-planning index.

This is a planning/evidence index only. It deliberately produces zero authorized
mounts until separate render + collision + safe-spawn evidence is explicitly
registered by a later promotion lot. Runtime directory scanning is forbidden.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-road-cell-mount-index-v1"
READINESS_SCHEMA = "grand-bruxelles-road-destination-readiness-catalog-v1"
CELL_MANIFEST_FORMAT = "grand-bruxelles-cell-maturity-v1"
PROJECT_ROOT = Path(__file__).resolve().parents[1]
CELL_MANIFEST_ROOT = PROJECT_ROOT / "data" / "cell_manifests"
CLOSED_KEYS = (
    "render_authorized",
    "collision_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
    "jouable_authorized",
)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_sha256(value: Any) -> bool:
    text = str(value or "").lower()
    return len(text) == 64 and all(ch in "0123456789abcdef" for ch in text)


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: expected object {path}")
    return value


def require_closed(mapping: dict[str, Any], keys: tuple[str, ...], label: str) -> None:
    for key in keys:
        if mapping.get(key) is not False:
            raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: {label} opened {key}")


def verify_readiness_semantic(readiness: dict[str, Any]) -> str:
    stored = str(readiness.get("semantic_sha256") or "").lower()
    if not is_sha256(stored):
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: readiness semantic sha invalid")
    unsigned = dict(readiness)
    unsigned.pop("semantic_sha256", None)
    expected = sha256_json(unsigned)
    if stored != expected:
        raise SystemExit(
            f"ROAD_CELL_MOUNT_INDEX_FAIL: readiness semantic drift stored={stored} expected={expected}"
        )
    return stored


def verify_cell_manifest_binding(
    project_root: Path,
    *,
    cell_id: str,
    grid_cell_id: str,
    bbox: list[Any],
    manifest_path: str,
    manifest_sha: str,
) -> None:
    relative = Path(manifest_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: unsafe cell manifest path {cell_id}")

    root = (project_root / "data" / "cell_manifests").resolve()
    resolved = (project_root / relative).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: cell manifest escaped root {cell_id}") from exc
    if not resolved.is_file():
        raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: cell manifest missing {cell_id}")

    actual_sha = sha256_file(resolved)
    if actual_sha != manifest_sha:
        raise SystemExit(
            f"ROAD_CELL_MOUNT_INDEX_FAIL: cell manifest bytes drift {cell_id} "
            f"stored={manifest_sha} actual={actual_sha}"
        )

    manifest = load_json(resolved)
    if manifest.get("format") != CELL_MANIFEST_FORMAT:
        raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: cell manifest format drift {cell_id}")
    if manifest.get("cell_id") != cell_id or manifest.get("crs") != "EPSG:31370":
        raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: cell manifest identity drift {cell_id}")
    if manifest.get("bbox") != bbox:
        raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: cell manifest bbox drift {cell_id}")
    if grid_cell_id != f"E{int(float(bbox[0]))}_N{int(float(bbox[1]))}":
        raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: grid cell identity drift {cell_id}")


def build_index(readiness: dict[str, Any], project_root: Path = PROJECT_ROOT) -> dict[str, Any]:
    if readiness.get("schema") != READINESS_SCHEMA:
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: readiness schema drift")
    if readiness.get("status") != "SOURCE_BACKED_REGISTERED_NOT_RENDERED":
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: readiness status drift")

    semantic_sha = verify_readiness_semantic(readiness)
    authorization = readiness.get("authorization") or {}
    require_closed(
        authorization,
        (
            "road_cell_mapping_authorized",
            "runtime_directory_scan_authorized",
            "runtime_mount_authorized",
            "render_authorized",
            "collision_authorized",
            "safe_spawn_authorized",
            "jouable_authorized",
        ),
        "readiness catalog",
    )

    destinations = readiness.get("destinations")
    if not isinstance(destinations, list) or int(readiness.get("destination_count", -1)) != len(destinations):
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: destination accounting drift")

    road_index: dict[str, Any] = {}
    cells: dict[str, Any] = {}
    seen_road_ids: set[int] = set()
    verified_manifests: set[tuple[str, str]] = set()
    for row in destinations:
        if not isinstance(row, dict):
            raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: malformed destination")
        road_id = int(row.get("road_osm_id", 0))
        destination_id = str(row.get("destination_id") or "")
        if road_id <= 0 or destination_id != f"road-{road_id}" or road_id in seen_road_ids:
            raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: invalid/duplicate road {road_id}")
        seen_road_ids.add(road_id)
        if row.get("readiness") != "REGISTERED_NOT_RENDERED":
            raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: readiness drift {road_id}")
        if row.get("cell_crs") != "EPSG:31370":
            raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: cell CRS drift {road_id}")
        require_closed(row, CLOSED_KEYS, f"destination {road_id}")

        cell_id = str(row.get("cell_id") or "")
        grid_cell_id = str(row.get("grid_cell_id") or "")
        manifest_path = str(row.get("cell_manifest_path") or "")
        manifest_sha = str(row.get("cell_manifest_sha256") or "").lower()
        bbox = row.get("cell_bbox")
        if (
            not cell_id
            or not grid_cell_id
            or not manifest_path.startswith("data/cell_manifests/")
            or not is_sha256(manifest_sha)
            or not isinstance(bbox, list)
            or len(bbox) != 4
        ):
            raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: cell identity drift {road_id}")

        binding_key = (manifest_path, manifest_sha)
        if binding_key not in verified_manifests:
            verify_cell_manifest_binding(
                project_root,
                cell_id=cell_id,
                grid_cell_id=grid_cell_id,
                bbox=bbox,
                manifest_path=manifest_path,
                manifest_sha=manifest_sha,
            )
            verified_manifests.add(binding_key)

        existing = cells.get(cell_id)
        identity = {
            "cell_id": cell_id,
            "grid_cell_id": grid_cell_id,
            "cell_crs": "EPSG:31370",
            "cell_bbox": bbox,
            "cell_manifest_path": manifest_path,
            "cell_manifest_sha256": manifest_sha,
        }
        if existing is None:
            cells[cell_id] = {
                **identity,
                "road_osm_ids": [],
                "road_count": 0,
                "render_ready": False,
                "collision_ready": False,
                "safe_spawn_ready": False,
                "mount_authorized": False,
            }
        else:
            for key, value in identity.items():
                if existing.get(key) != value:
                    raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: inconsistent cell identity {cell_id}")
        cells[cell_id]["road_osm_ids"].append(road_id)

        road_index[destination_id] = {
            "road_osm_id": road_id,
            "cell_id": cell_id,
            "cell_manifest_path": manifest_path,
            "cell_manifest_sha256": manifest_sha,
            "mount_authorized": False,
        }

    ordered_cells: dict[str, Any] = {}
    for cell_id in sorted(cells):
        item = cells[cell_id]
        item["road_osm_ids"] = sorted(item["road_osm_ids"])
        item["road_count"] = len(item["road_osm_ids"])
        ordered_cells[cell_id] = item

    payload: dict[str, Any] = {
        "format": FORMAT,
        "readiness_catalog_semantic_sha256": semantic_sha,
        "destination_count": len(road_index),
        "cell_count": len(ordered_cells),
        "authorized_mount_count": 0,
        "authorized_mounts": [],
        "deterministic_manifest_lookup_required": True,
        "runtime_directory_scan_authorized": False,
        "road_index": {key: road_index[key] for key in sorted(road_index, key=lambda x: int(x.split("-", 1)[1]))},
        "cells": ordered_cells,
        "authorization": {
            "evidence_only": True,
            "road_cell_mapping_authorized": False,
            "runtime_mount_authorized": False,
            "render_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        },
    }
    payload["index_sha256"] = sha256_json(payload)
    return payload


def validate_index(index: dict[str, Any]) -> None:
    if index.get("format") != FORMAT:
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: format drift")
    if index.get("deterministic_manifest_lookup_required") is not True:
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: deterministic lookup rail missing")
    if index.get("runtime_directory_scan_authorized") is not False:
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: directory scan opened")
    if index.get("authorized_mount_count") != 0 or index.get("authorized_mounts") != []:
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: unauthorized mount materialized")
    auth = index.get("authorization") or {}
    if auth.get("evidence_only") is not True:
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: evidence-only rail missing")
    require_closed(auth, ("road_cell_mapping_authorized",) + CLOSED_KEYS, "mount index")

    roads = index.get("road_index")
    cells = index.get("cells")
    if not isinstance(roads, dict) or int(index.get("destination_count", -1)) != len(roads):
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: road accounting drift")
    if not isinstance(cells, dict) or int(index.get("cell_count", -1)) != len(cells):
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: cell accounting drift")
    for destination_id, row in roads.items():
        if row.get("mount_authorized") is not False or row.get("cell_id") not in cells:
            raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: road mount drift {destination_id}")
    for cell_id, row in cells.items():
        if any(row.get(key) is not False for key in ("render_ready", "collision_ready", "safe_spawn_ready", "mount_authorized")):
            raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: cell readiness opened {cell_id}")
        if int(row.get("road_count", -1)) != len(row.get("road_osm_ids") or []):
            raise SystemExit(f"ROAD_CELL_MOUNT_INDEX_FAIL: cell road accounting drift {cell_id}")

    stored = str(index.get("index_sha256") or "").lower()
    unsigned = dict(index)
    unsigned.pop("index_sha256", None)
    if not is_sha256(stored) or stored != sha256_json(unsigned):
        raise SystemExit("ROAD_CELL_MOUNT_INDEX_FAIL: index sha drift")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--readiness",
        type=Path,
        default=Path("data/provenance/brussels_road_destination_readiness_catalog.json"),
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    readiness = load_json(args.readiness)
    index = build_index(readiness)
    validate_index(index)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(index, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "ROAD_CELL_MOUNT_INDEX_OK "
        f"destinations={index['destination_count']} cells={index['cell_count']} authorized_mounts=0 "
        f"sha256={index['index_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
