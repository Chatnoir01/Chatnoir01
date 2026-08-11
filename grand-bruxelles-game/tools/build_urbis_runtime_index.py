#!/usr/bin/env python3
"""Build a compact Godot streaming index from materialized UrbIS cell manifests."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

TOOLS_DIR = Path(__file__).resolve().parent
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


def build_index(source_root: Path, resource_prefix: str) -> dict[str, Any]:
    cells: list[dict[str, Any]] = []
    for manifest_path in sorted(source_root.glob("*/manifest.json")):
        manifest = load_cell_manifest(manifest_path)
        runtime = manifest["runtime"]
        cell_dir = manifest_path.parent
        bounds = world_bounds(manifest["bbox"])
        center = [round((bounds[0] + bounds[2]) * 0.5, 3), round((bounds[1] + bounds[3]) * 0.5, 3)]
        cells.append(
            {
                "cell_id": str(manifest["cell_id"]),
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
        "format": "grand-bruxelles-urbis-runtime-index-v1",
        "coordinate_system": "current_game_world_xz_metres",
        "cell_count": len(cells),
        "cells": cells,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Index materialized UrbIS runtime cells for Godot streaming")
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--resource-prefix", default="res://data/urbis/remaining_brussels/cells")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    index = build_index(args.source_root, args.resource_prefix)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(index, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"runtime index: {index['cell_count']} cells -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
