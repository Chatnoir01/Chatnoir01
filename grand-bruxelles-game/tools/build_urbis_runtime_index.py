#!/usr/bin/env python3
"""Build a compact Godot streaming index from materialized UrbIS cell manifests.

Materialized seam/reference cells may intentionally be retained even when their
production geometry belongs to another workstream. Runtime exclusions keep that
source evidence available while preventing duplicate geometry from being loaded
by this branch's Godot streamer.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

TOOLS_DIR = Path(__file__).resolve().parent
ROOT = TOOLS_DIR.parent
DEFAULT_EXCLUSIONS = ROOT / "data" / "urbis" / "remaining_brussels" / "runtime_exclusions.json"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from make_urbis_cell_runtime import game_point


def load_cell_manifest(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != "grand-bruxelles-urbis-built-cell-v1":
        raise ValueError(f"unsupported cell manifest: {path}")
    bbox = payload.get("bbox")
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise ValueError(f"invalid bbox in {path}")
    runtime = payload.get("runtime")
    if not isinstance(runtime, dict):
        raise ValueError(f"missing runtime section in {path}")
    return payload


def load_exclusions(path: Path | None) -> dict[str, dict[str, Any]]:
    if path is None or not path.exists():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != "grand-bruxelles-runtime-exclusions-v1":
        raise ValueError(f"unsupported runtime exclusions format: {path}")
    entries = payload.get("excluded_cells")
    if not isinstance(entries, list):
        raise ValueError(f"runtime exclusions must contain excluded_cells: {path}")
    result: dict[str, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError(f"invalid runtime exclusion entry: {entry!r}")
        cell_id = str(entry.get("cell_id", "")).strip()
        if not cell_id:
            raise ValueError("runtime exclusion entry is missing cell_id")
        if cell_id in result:
            raise ValueError(f"duplicate runtime exclusion for {cell_id}")
        result[cell_id] = entry
    return result


def world_bounds(bbox: list[float]) -> list[float]:
    min_e, min_n, max_e, max_n = [float(value) for value in bbox]
    southwest = game_point([min_e, min_n])
    northeast = game_point([max_e, max_n])
    xs = [southwest[0], northeast[0]]
    zs = [southwest[1], northeast[1]]
    return [round(min(xs), 3), round(min(zs), 3), round(max(xs), 3), round(max(zs), 3)]


def resource_path(source_root: Path, cell_dir: Path, relative_file: str, resource_prefix: str) -> str:
    relative_cell = cell_dir.relative_to(source_root).as_posix()
    prefix = resource_prefix.rstrip("/")
    return f"{prefix}/{relative_cell}/{relative_file}"


def build_index(
    source_root: Path,
    resource_prefix: str,
    exclusions: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    excluded = exclusions or {}
    cells: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for manifest_path in sorted(source_root.glob("*/manifest.json")):
        manifest = load_cell_manifest(manifest_path)
        cell_id = str(manifest["cell_id"])
        if cell_id in excluded:
            entry = excluded[cell_id]
            skipped.append(
                {
                    "cell_id": cell_id,
                    "owner": str(entry.get("owner", "")),
                    "reason": str(entry.get("reason", "")),
                }
            )
            continue
        runtime = manifest["runtime"]
        cell_dir = manifest_path.parent
        bounds = world_bounds(manifest["bbox"])
        center = [round((bounds[0] + bounds[2]) * 0.5, 3), round((bounds[1] + bounds[3]) * 0.5, 3)]
        cells.append(
            {
                "cell_id": cell_id,
                "source_bbox": manifest["bbox"],
                "world_bounds": bounds,
                "world_center": center,
                "geometry_path": resource_path(source_root, cell_dir, str(runtime["geometry_file"]), resource_prefix),
                "network_path": resource_path(source_root, cell_dir, str(runtime["network_file"]), resource_prefix),
                "geometry_stats": runtime.get("geometry_stats", {}),
                "network_stats": runtime.get("network_stats", {}),
            }
        )
    return {
        "format": "grand-bruxelles-urbis-runtime-index-v2",
        "coordinate_system": "current_game_world_xz_metres",
        "cell_count": len(cells),
        "excluded_cell_count": len(skipped),
        "excluded_cells": skipped,
        "cells": cells,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Index materialized UrbIS runtime cells for Godot streaming")
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--resource-prefix", default="res://data/urbis/remaining_brussels/cells")
    parser.add_argument("--exclusions", type=Path, default=DEFAULT_EXCLUSIONS)
    parser.add_argument("--no-exclusions", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    exclusions = {} if args.no_exclusions else load_exclusions(args.exclusions)
    index = build_index(args.source_root, args.resource_prefix, exclusions)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(index, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(
        f"runtime index: {index['cell_count']} streamable cells, "
        f"{index['excluded_cell_count']} excluded seam/reference cells -> {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
