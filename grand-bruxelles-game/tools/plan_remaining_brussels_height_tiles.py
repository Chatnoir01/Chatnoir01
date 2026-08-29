#!/usr/bin/env python3
"""Plan official UrbIS DSM/DTM 1 km tiles for materialized Brussels cells.

The rest-of-Brussels workstream stores 500 m cells in Belgian Lambert 72
(EPSG:31370). UrbIS 2021 DSM/DTM downloads are distributed as 1 km grid tiles
whose six-digit code is the kilometre easting followed by kilometre northing.
This tool derives the minimal authoritative raster-tile set needed for a list of
materialized cells without guessing from neighbourhood names or visual extent.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

CELL_RE = re.compile(r"^bxl-e(?P<e>\d+)-n(?P<n>\d+)-s(?P<size>\d+)$")
DSM_DATASET_ID = "8c2d921e-6a53-11ed-bfb5-010101010000"
DTM_DATASET_ID = "1d7bd49d-fe83-4388-af85-6f5dc8ec7909"


def parse_cell_id(cell_id: str) -> tuple[int, int, int]:
    match = CELL_RE.fullmatch(cell_id)
    if not match:
        raise ValueError(f"Invalid cell id: {cell_id}")
    easting = int(match.group("e"))
    northing = int(match.group("n"))
    size = int(match.group("size"))
    if size <= 0:
        raise ValueError(f"Cell size must be positive: {cell_id}")
    return easting, northing, size


def tile_codes_for_bbox(min_x: int, min_y: int, max_x: int, max_y: int) -> list[str]:
    if max_x <= min_x or max_y <= min_y:
        raise ValueError("Bounding box must have positive area")
    # Use max-1 millimetre semantics so a cell ending exactly on a kilometre
    # boundary does not request the adjacent raster tile unnecessarily.
    last_x = max_x - 1
    last_y = max_y - 1
    xs = range(min_x // 1000, last_x // 1000 + 1)
    ys = range(min_y // 1000, last_y // 1000 + 1)
    return [f"{x:03d}{y:03d}" for x in xs for y in ys]


def tile_codes_for_cells(cell_ids: list[str]) -> list[str]:
    codes: set[str] = set()
    for cell_id in cell_ids:
        easting, northing, size = parse_cell_id(cell_id)
        codes.update(tile_codes_for_bbox(easting, northing, easting + size, northing + size))
    return sorted(codes)


def build_plan(cell_ids: list[str]) -> dict:
    if not cell_ids:
        raise ValueError("At least one materialized cell is required")
    parsed = [parse_cell_id(cell_id) for cell_id in cell_ids]
    min_x = min(e for e, _, _ in parsed)
    min_y = min(n for _, n, _ in parsed)
    max_x = max(e + size for e, _, size in parsed)
    max_y = max(n + size for _, n, size in parsed)
    return {
        "schema": 1,
        "format": "grand-bruxelles-height-tile-plan-v1",
        "source_crs": "EPSG:31370",
        "materialized_cells": sorted(cell_ids),
        "bbox_epsg31370": [min_x, min_y, max_x, max_y],
        "expected_1km_tile_codes": tile_codes_for_cells(cell_ids),
        "official_sources": {
            "dsm": {
                "name": "Paradigm UrbIS Digital Surface Model 2021",
                "dataset_id": DSM_DATASET_ID,
                "atom_feed": f"https://urbisdownload.datastore.brussels/atomfeed/{DSM_DATASET_ID}-en.xml",
            },
            "dtm": {
                "name": "Paradigm UrbIS Digital Terrain Model 2021",
                "dataset_id": DTM_DATASET_ID,
                "atom_feed": f"https://urbisdownload.datastore.brussels/atomfeed/{DTM_DATASET_ID}-en.xml",
            },
        },
        "height_method_target": "DSM minus DTM sampled inside official UrbIS building footprints",
        "notes": "Tile selection is geometric only. A later step must resolve each code against the official Atom feeds, download and hash the exact source archives, align DSM/DTM grids, then derive per-building heights with quality metrics.",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cells", nargs="+", required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan = build_plan(args.cells)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(plan, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("REMAINING_BRUSSELS_HEIGHT_TILE_PLAN_OK", {
        "cells": len(plan["materialized_cells"]),
        "tiles": plan["expected_1km_tile_codes"],
        "bbox": plan["bbox_epsg31370"],
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
