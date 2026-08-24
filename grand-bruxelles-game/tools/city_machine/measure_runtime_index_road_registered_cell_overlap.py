#!/usr/bin/env python3
"""Measure registered-cell overlap for the exact runtime-index-eligible roads."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
DEFAULT_SOURCE = PROJECT / "data/osm/vertical_slice_01.game.json"
DEFAULT_INDEX = PROJECT / "data/runtime/road_destination_runtime_index.json"
DEFAULT_CELLS = PROJECT / "data/provenance/brussels_registered_cell_manifest_index.json"
LEGACY = HERE / "measure_road_registered_cell_overlap.py"
CATALOG_SCRIPT = PROJECT / "tools/build_road_destination_catalog.py"
ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected object: {path}")
    return value


def measure(source: Path, index_path: Path, cells_path: Path) -> dict[str, Any]:
    index = load(index_path)
    if index.get("format") != "grand-bruxelles-road-runtime-index-v1" or index.get("source_lookup_only") is not True:
        raise ValueError("runtime index contract mismatch")
    auth = index.get("authorization")
    if not isinstance(auth, dict) or auth.get("source_lookup_only") is not True:
        raise ValueError("runtime index authorization missing")
    for key, value in auth.items():
        if key.endswith("_authorized") and value is not False:
            raise ValueError(f"runtime index must keep {key}=false")

    rel = str(source.relative_to(PROJECT))
    docs = index.get("documents")
    matches = [row for row in docs or [] if isinstance(row, dict) and row.get("path") == rel]
    if len(matches) != 1:
        raise ValueError("runtime index descriptor invalid")
    descriptor = matches[0]
    actual_sha = hashlib.sha256(source.read_bytes()).hexdigest()
    if actual_sha != descriptor.get("sha256"):
        raise ValueError("road source SHA-256 mismatch")
    indexed_ids = descriptor.get("road_ids")
    if not isinstance(indexed_ids, list) or indexed_ids != sorted(indexed_ids) or len(set(indexed_ids)) != len(indexed_ids):
        raise ValueError("runtime descriptor road IDs invalid")

    road_doc = load(source)
    if road_doc.get("format") != "grand-bruxelles-osm-v1" or road_doc.get("source") != "OpenStreetMap contributors via Overpass API" or road_doc.get("license") != "ODbL-1.0":
        raise ValueError("road source provenance drift")
    roads = road_doc.get("roads")
    if not isinstance(roads, list) or not roads:
        raise ValueError("road source has no roads")

    catalog = load_module(CATALOG_SCRIPT, "road_destination_catalog_measurement")
    eligible: dict[int, dict[str, Any]] = {}
    rejected_drivable = 0
    for raw in roads:
        if not isinstance(raw, dict):
            continue
        signature = catalog.road_signature(raw)
        if signature is None:
            if raw.get("drivable") is True:
                rejected_drivable += 1
            continue
        eligible[int(signature["osm_id"])] = signature
    if sorted(eligible) != indexed_ids:
        raise ValueError("eligible road IDs drift from runtime descriptor")

    legacy = load_module(LEGACY, "legacy_overlap_geometry")
    cell_index, cells = legacy.load_registered_cells(cells_path)
    overlaps: list[dict[str, Any]] = []
    all_e: list[float] = []
    all_n: list[float] = []
    point_count = 0
    for osm_id in indexed_ids:
        road = eligible[osm_id]
        projected: list[tuple[float, float]] = []
        for x, z in road["points"]:
            e, n = ORIGIN_E + float(x), ORIGIN_N - float(z)
            if not math.isfinite(e) or not math.isfinite(n):
                raise ValueError(f"road {osm_id} projected point non-finite")
            projected.append((e, n))
            all_e.append(e)
            all_n.append(n)
            point_count += 1
        matched: list[dict[str, Any]] = []
        for cell in cells:
            bbox = cell["bbox"]
            point_hits = sum(1 for e, n in projected if legacy.point_in_bbox(e, n, bbox))
            segment_hits = sum(1 for a, b in zip(projected, projected[1:]) if legacy.segment_intersects_bbox(a, b, bbox))
            if point_hits or segment_hits:
                matched.append({"cell_id": cell["cell_id"], "point_hits": point_hits, "segment_hits": segment_hits})
        if matched:
            overlaps.append({
                "osm_id": osm_id,
                "name": road["name"],
                "class": road["class"],
                "cells": sorted(matched, key=lambda value: value["cell_id"]),
            })
    overlaps.sort(key=lambda value: value["osm_id"])

    core = {
        "schema": "grand-bruxelles-road-registered-cell-overlap-measurement-v2",
        "road_runtime_index": str(index_path.relative_to(PROJECT)),
        "road_runtime_index_format": index["format"],
        "road_runtime_catalog_sha256": index.get("catalog_sha256"),
        "road_source": rel,
        "road_source_sha256": actual_sha,
        "road_source_provider": road_doc["source"],
        "road_source_license": road_doc["license"],
        "raw_road_count": len(roads),
        "rejected_drivable_road_count": rejected_drivable,
        "road_count": len(indexed_ids),
        "runtime_descriptor_road_count": len(indexed_ids),
        "road_point_count": point_count,
        "road_lambert72_bbox": [min(all_e), min(all_n), max(all_e), max(all_n)],
        "frame": {
            "crs": "EPSG:31370",
            "origin_easting_m": ORIGIN_E,
            "origin_northing_m": ORIGIN_N,
            "formula": "E=origin_easting_m+x;N=origin_northing_m-z",
        },
        "registered_cell_index": str(cells_path.relative_to(PROJECT)),
        "registered_cell_index_semantic_sha256": cell_index.get("semantic_sha256"),
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
    result["semantic_sha256"] = legacy.canonical_sha256(core)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--road-source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--road-index", type=Path, default=DEFAULT_INDEX)
    parser.add_argument("--cell-index", type=Path, default=DEFAULT_CELLS)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = measure(args.road_source.resolve(), args.road_index.resolve(), args.cell_index.resolve())
    except Exception as exc:
        print(f"ROAD_REGISTERED_CELL_OVERLAP_V2_RED: {exc}")
        return 2
    text = json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")
    print(
        "ROAD_REGISTERED_CELL_OVERLAP_V2_GREEN "
        f"indexed_roads={result['road_count']} raw_roads={result['raw_road_count']} "
        f"cells={result['registered_cell_count']} overlap={result['overlapping_road_count']} "
        f"sha256={result['semantic_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
