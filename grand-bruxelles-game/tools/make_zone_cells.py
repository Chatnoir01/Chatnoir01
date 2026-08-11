#!/usr/bin/env python3
"""Generate deterministic Lambert72 work cells from an official zone boundary.

Input must be GeoJSON already expressed in EPSG:31370. The script never invents
municipal bounds: it derives the grid envelope from the supplied official
geometry and writes a manifest that can feed fetch_urbis_wfs_bbox.py.

The generated cells cover the boundary envelope. Cells with no UrbIS features
can be discarded by the downstream fetch/build pipeline, which keeps this tool
dependency-free and reproducible in CI.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Iterable

CRS = "EPSG:31370"
DEFAULT_CELL_SIZE = 500.0


def iter_positions(coords: object) -> Iterable[tuple[float, float]]:
    if not isinstance(coords, list):
        return
    if len(coords) >= 2 and all(isinstance(v, (int, float)) for v in coords[:2]):
        yield float(coords[0]), float(coords[1])
        return
    for child in coords:
        yield from iter_positions(child)


def collect_positions(payload: dict) -> list[tuple[float, float]]:
    payload_type = payload.get("type")
    positions: list[tuple[float, float]] = []

    if payload_type == "FeatureCollection":
        for feature in payload.get("features", []):
            geometry = feature.get("geometry") or {}
            positions.extend(iter_positions(geometry.get("coordinates")))
    elif payload_type == "Feature":
        geometry = payload.get("geometry") or {}
        positions.extend(iter_positions(geometry.get("coordinates")))
    else:
        positions.extend(iter_positions(payload.get("coordinates")))

    if not positions:
        raise ValueError("input contains no coordinate positions")
    return positions


def aligned_floor(value: float, step: float) -> float:
    return math.floor(value / step) * step


def aligned_ceil(value: float, step: float) -> float:
    return math.ceil(value / step) * step


def build_cells(
    min_e: float,
    min_n: float,
    max_e: float,
    max_n: float,
    cell_size: float,
    prefix: str,
) -> list[dict]:
    start_e = aligned_floor(min_e, cell_size)
    start_n = aligned_floor(min_n, cell_size)
    end_e = aligned_ceil(max_e, cell_size)
    end_n = aligned_ceil(max_n, cell_size)

    cols = int(round((end_e - start_e) / cell_size))
    rows = int(round((end_n - start_n) / cell_size))
    cells: list[dict] = []

    for row in range(rows):
        for col in range(cols):
            cell_min_e = start_e + col * cell_size
            cell_min_n = start_n + row * cell_size
            cell_max_e = cell_min_e + cell_size
            cell_max_n = cell_min_n + cell_size
            cells.append(
                {
                    "id": f"{prefix}-{row:03d}-{col:03d}",
                    "row": row,
                    "col": col,
                    "bbox": [cell_min_e, cell_min_n, cell_max_e, cell_max_n],
                    "fetch_command": (
                        "python tools/fetch_urbis_wfs_bbox.py "
                        f"--output-dir data/processed/{prefix}/{prefix}-{row:03d}-{col:03d} "
                        f"--bbox {cell_min_e},{cell_min_n},{cell_max_e},{cell_max_n}"
                    ),
                }
            )
    return cells


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create deterministic 500 m Lambert72 work cells for a Brussels zone"
    )
    parser.add_argument("--boundary", type=Path, required=True, help="official GeoJSON in EPSG:31370")
    parser.add_argument("--zone-id", required=True, help="stable lowercase zone identifier")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cell-size", type=float, default=DEFAULT_CELL_SIZE)
    args = parser.parse_args()

    if args.cell_size <= 0:
        parser.error("--cell-size must be greater than zero")
    if not args.zone_id or any(ch.isspace() for ch in args.zone_id):
        parser.error("--zone-id must be a non-empty identifier without spaces")

    payload = json.loads(args.boundary.read_text(encoding="utf-8"))
    positions = collect_positions(payload)
    eastings = [position[0] for position in positions]
    northings = [position[1] for position in positions]
    source_bbox = [min(eastings), min(northings), max(eastings), max(northings)]

    cells = build_cells(*source_bbox, args.cell_size, args.zone_id)
    manifest = {
        "format": "grand-bruxelles-zone-cells-v1",
        "zone_id": args.zone_id,
        "crs": CRS,
        "boundary_source": str(args.boundary),
        "source_bbox": source_bbox,
        "cell_size_m": args.cell_size,
        "cell_count": len(cells),
        "cells": cells,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{args.zone_id}: {len(cells)} cells -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
