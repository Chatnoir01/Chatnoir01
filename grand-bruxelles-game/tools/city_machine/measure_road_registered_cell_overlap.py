#!/usr/bin/env python3
"""Measure indexed OSM road overlap with registered Lambert72 cells.

Evidence only. The deterministic runtime road index is the source authority.
This script verifies its source descriptor against the current OSM bytes,
projects roads through the already-proven project frame, and measures overlap.
It never authorizes road->cell mapping, mount, render, collision, safe spawn,
or JOUABLE promotion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
DEFAULT_ROAD_SOURCE = PROJECT / "data/osm/vertical_slice_01.game.json"
DEFAULT_ROAD_INDEX = PROJECT / "data/runtime/road_destination_runtime_index.json"
DEFAULT_CELL_INDEX = PROJECT / "data/provenance/brussels_registered_cell_manifest_index.json"
ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(raw)


def fail(message: str) -> int:
    print(f"ROAD_REGISTERED_CELL_OVERLAP_RED: {message}")
    return 2


def point_in_bbox(x: float, y: float, bbox: list[float]) -> bool:
    return bbox[0] <= x <= bbox[2] and bbox[1] <= y <= bbox[3]


def segment_intersects_bbox(a: tuple[float, float], b: tuple[float, float], bbox: list[float]) -> bool:
    x0, y0 = a
    x1, y1 = b
    dx = x1 - x0
    dy = y1 - y0
    p = (-dx, dx, -dy, dy)
    q = (x0 - bbox[0], bbox[2] - x0, y0 - bbox[1], bbox[3] - y0)
    u0, u1 = 0.0, 1.0
    for pi, qi in zip(p, q):
        if pi == 0.0:
            if qi < 0.0:
                return False
            continue
        t = qi / pi
        if pi < 0.0:
            if t > u1:
                return False
            u0 = max(u0, t)
        else:
            if t < u0:
                return False
            u1 = min(u1, t)
    return u0 <= u1


def load_road_index(index_path: Path, road_source: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    index = json.loads(index_path.read_text(encoding="utf-8"))
    if index.get("format") != "grand-bruxelles-road-runtime-index-v1":
        raise ValueError("runtime road index format mismatch")
    if index.get("source_lookup_only") is not True:
        raise ValueError("runtime road index must remain source_lookup_only")
    authorization = index.get("authorization")
    if not isinstance(authorization, dict) or authorization.get("source_lookup_only") is not True:
        raise ValueError("runtime road index source lookup authorization missing")
    for key, value in authorization.items():
        if key.endswith("_authorized") and value is not False:
            raise ValueError(f"runtime road index authorization rail opened: {key}")
    catalog_sha = str(index.get("catalog_sha256", ""))
    if len(catalog_sha) != 64:
        raise ValueError("runtime road index catalog SHA-256 invalid")
    documents = index.get("documents")
    if not isinstance(documents, list) or not documents:
        raise ValueError("runtime road index has no documents")
    canonical_rel = "data/osm/vertical_slice_01.game.json"
    matches = [row for row in documents if isinstance(row, dict) and row.get("path") == canonical_rel]
    if len(matches) != 1:
        raise ValueError("runtime road index must contain exactly one canonical road source descriptor")
    descriptor = matches[0]
    expected_sha = str(descriptor.get("sha256", ""))
    actual_sha = sha256_bytes(road_source.read_bytes())
    if len(expected_sha) != 64 or actual_sha != expected_sha:
        raise ValueError(f"road source SHA-256 mismatch: {actual_sha}")
    road_ids = descriptor.get("road_ids")
    if not isinstance(road_ids, list) or not road_ids or not all(isinstance(v, int) for v in road_ids):
        raise ValueError("runtime road index road IDs invalid")
    if len(set(road_ids)) != len(road_ids):
        raise ValueError("runtime road index road IDs must be unique")
    return index, descriptor


def load_registered_cells(index_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    index = json.loads(index_path.read_text(encoding="utf-8"))
    if index.get("schema") != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise ValueError("registered cell index schema mismatch")
    for flag in (
        "road_crosswalk_authorized",
        "runtime_directory_scan_authorized",
        "runtime_mount_authorized",
        "rendered_geometry_authorized",
        "collision_authorized",
        "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ):
        if index.get(flag) is not False:
            raise ValueError(f"registered cell index must keep {flag}=false")
    entries = index.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValueError("registered cell index has no entries")
    if index.get("registered_cell_count") != len(entries):
        raise ValueError("registered cell count mismatch")
    seen: set[str] = set()
    checked: list[dict[str, Any]] = []
    for entry in entries:
        cell_id = str(entry.get("cell_id", ""))
        if not cell_id or cell_id in seen:
            raise ValueError("registered cell IDs must be unique and non-empty")
        seen.add(cell_id)
        if entry.get("crs") != "EPSG:31370":
            raise ValueError(f"registered cell {cell_id} is not EPSG:31370")
        bbox = entry.get("bbox")
        if not isinstance(bbox, list) or len(bbox) != 4 or not all(isinstance(v, (int, float)) and math.isfinite(float(v)) for v in bbox):
            raise ValueError(f"registered cell {cell_id} bbox invalid")
        bbox = [float(v) for v in bbox]
        if not (bbox[0] < bbox[2] and bbox[1] < bbox[3]):
            raise ValueError(f"registered cell {cell_id} bbox degenerate")
        for key, value in entry.items():
            if key.endswith("_authorized") and value is not False:
                raise ValueError(f"registered cell {cell_id} authorization rail opened: {key}")
        rel = Path(str(entry.get("manifest_path", "")))
        if rel.is_absolute() or ".." in rel.parts:
            raise ValueError(f"registered cell {cell_id} manifest path unsafe")
        manifest_path = PROJECT / rel
        raw = manifest_path.read_bytes()
        if sha256_bytes(raw) != entry.get("manifest_sha256"):
            raise ValueError(f"registered cell {cell_id} manifest SHA-256 mismatch")
        manifest = json.loads(raw)
        if manifest.get("cell_id") != cell_id or manifest.get("crs") != "EPSG:31370":
            raise ValueError(f"registered cell {cell_id} manifest identity mismatch")
        if [float(v) for v in manifest.get("bbox", [])] != bbox:
            raise ValueError(f"registered cell {cell_id} manifest bbox mismatch")
        checked.append({"cell_id": cell_id, "bbox": bbox, "manifest_sha256": entry["manifest_sha256"]})
    return index, checked


def measure(road_source: Path, road_index_path: Path, cell_index: Path) -> dict[str, Any]:
    road_bytes = road_source.read_bytes()
    road_index, descriptor = load_road_index(road_index_path, road_source)
    road_sha = sha256_bytes(road_bytes)
    roads_payload = json.loads(road_bytes)
    if roads_payload.get("format") != "grand-bruxelles-osm-v1":
        raise ValueError("road source format drift")
    if roads_payload.get("source") != "OpenStreetMap contributors via Overpass API":
        raise ValueError("road source provider drift")
    if roads_payload.get("license") != "ODbL-1.0":
        raise ValueError("road source license drift")
    roads = roads_payload.get("roads")
    if not isinstance(roads, list) or not roads:
        raise ValueError("road source has no roads")
    expected_count = roads_payload.get("stats", {}).get("roads")
    if expected_count != len(roads):
        raise ValueError(f"road count drift: stats={expected_count} actual={len(roads)}")
    source_ids = [row.get("osm_id") for row in roads if isinstance(row, dict)]
    if len(source_ids) != len(roads) or not all(isinstance(v, int) for v in source_ids):
        raise ValueError("road source OSM IDs invalid")
    if len(set(source_ids)) != len(source_ids):
        raise ValueError("road source OSM IDs must be unique")
    if set(source_ids) != set(descriptor["road_ids"]):
        raise ValueError("runtime road index membership differs from road source")

    index, cells = load_registered_cells(cell_index)
    transformed_points = 0
    all_e: list[float] = []
    all_n: list[float] = []
    overlaps: list[dict[str, Any]] = []
    for road in roads:
        osm_id = int(road["osm_id"])
        points = road.get("points")
        if not isinstance(points, list) or len(points) < 2:
            raise ValueError(f"road {osm_id} requires at least two points")
        projected: list[tuple[float, float]] = []
        for point in points:
            if not isinstance(point, list) or len(point) != 2:
                raise ValueError(f"road {osm_id} point invalid")
            x, z = float(point[0]), float(point[1])
            if not math.isfinite(x) or not math.isfinite(z):
                raise ValueError(f"road {osm_id} point non-finite")
            e, n = ORIGIN_E + x, ORIGIN_N - z
            projected.append((e, n))
            all_e.append(e)
            all_n.append(n)
            transformed_points += 1
        matched: list[dict[str, Any]] = []
        for cell in cells:
            bbox = cell["bbox"]
            point_hits = sum(1 for e, n in projected if point_in_bbox(e, n, bbox))
            segment_hits = sum(1 for a, b in zip(projected, projected[1:]) if segment_intersects_bbox(a, b, bbox))
            if point_hits or segment_hits:
                matched.append({"cell_id": cell["cell_id"], "point_hits": point_hits, "segment_hits": segment_hits})
        if matched:
            overlaps.append({
                "osm_id": osm_id,
                "name": str(road.get("name") or ""),
                "class": str(road.get("class") or ""),
                "cells": sorted(matched, key=lambda value: value["cell_id"]),
            })
    overlaps.sort(key=lambda value: value["osm_id"])
    core = {
        "schema": "grand-bruxelles-road-registered-cell-overlap-measurement-v2",
        "road_runtime_index": str(road_index_path.relative_to(PROJECT)) if road_index_path.is_relative_to(PROJECT) else str(road_index_path),
        "road_runtime_index_format": road_index["format"],
        "road_runtime_catalog_sha256": road_index["catalog_sha256"],
        "road_source": str(road_source.relative_to(PROJECT)) if road_source.is_relative_to(PROJECT) else str(road_source),
        "road_source_sha256": road_sha,
        "road_source_provider": roads_payload["source"],
        "road_source_license": roads_payload["license"],
        "road_count": len(roads),
        "road_point_count": transformed_points,
        "road_lambert72_bbox": [min(all_e), min(all_n), max(all_e), max(all_n)],
        "frame": {
            "crs": "EPSG:31370",
            "origin_easting_m": ORIGIN_E,
            "origin_northing_m": ORIGIN_N,
            "formula": "E=origin_easting_m+x;N=origin_northing_m-z",
        },
        "registered_cell_index": str(cell_index.relative_to(PROJECT)) if cell_index.is_relative_to(PROJECT) else str(cell_index),
        "registered_cell_index_semantic_sha256": index.get("semantic_sha256"),
        "registered_cell_count": len(cells),
        "cell_crs": "EPSG:31370",
        "overlapping_road_count": len(overlaps),
        "overlaps": overlaps,
        "road_cell_mapping_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }
    result = dict(core)
    result["semantic_sha256"] = canonical_sha256(core)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--road-source", type=Path, default=DEFAULT_ROAD_SOURCE)
    parser.add_argument("--road-index", type=Path, default=DEFAULT_ROAD_INDEX)
    parser.add_argument("--cell-index", type=Path, default=DEFAULT_CELL_INDEX)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = measure(args.road_source.resolve(), args.road_index.resolve(), args.cell_index.resolve())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return fail(str(exc))
    text = json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")
    print(
        "ROAD_REGISTERED_CELL_OVERLAP_OK "
        f"roads={result['road_count']} cells={result['registered_cell_count']} "
        f"overlapping_roads={result['overlapping_road_count']} semantic_sha256={result['semantic_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
