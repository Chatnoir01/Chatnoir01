#!/usr/bin/env python3
"""Select one globally unique, not-yet-materialized seed cell per zone in a wave.

This tool composes the single-zone selector with the project catalog. It is
important for 500 m Lambert72 cells that can intersect several municipalities:
a cell selected for the first zone becomes forbidden for the next zones in the
same batch, preventing duplicate WFS work and duplicate game geometry.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

TOOLS_DIR = Path(__file__).resolve().parent
ROOT = TOOLS_DIR.parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from select_zone_seed_cell import load_existing_cell_ids, load_manifest, select_seed

DEFAULT_CATALOG = ROOT / "data" / "remaining_brussels_zones.json"
DEFAULT_GRID_ROOT = ROOT / "data" / "processed" / "remaining_brussels" / "cells"
DEFAULT_CELL_ROOT = ROOT / "data" / "urbis" / "remaining_brussels" / "cells"
DEFAULT_EXCLUSIONS = ROOT / "data" / "urbis" / "remaining_brussels" / "runtime_exclusions.json"
FORMAT = "grand-bruxelles-wave-seeds-v1"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_excluded_ids(path: Path | None) -> set[str]:
    if path is None or not path.exists():
        return set()
    payload = load_json(path)
    if payload.get("format") != "grand-bruxelles-runtime-exclusions-v1":
        raise ValueError(f"unsupported runtime exclusions format: {path}")
    result: set[str] = set()
    for entry in payload.get("excluded_cells", []):
        if not isinstance(entry, dict):
            raise ValueError(f"invalid runtime exclusion entry in {path}")
        cell_id = str(entry.get("cell_id", "")).strip()
        if not cell_id:
            raise ValueError(f"runtime exclusion missing cell_id in {path}")
        result.add(cell_id)
    return result


def zones_for_wave(catalog: dict[str, Any], wave: str) -> list[dict[str, Any]]:
    zones = catalog.get("zones")
    if not isinstance(zones, list):
        raise ValueError("catalog must contain zones")
    selected = [zone for zone in zones if isinstance(zone, dict) and str(zone.get("wave", "")) == wave]
    if not selected:
        raise ValueError(f"catalog contains no zones for wave {wave}")
    selected.sort(key=lambda zone: (int(zone.get("priority", 9999)), str(zone.get("id", ""))))
    return selected


def select_wave_seeds(
    catalog: dict[str, Any],
    wave: str,
    grid_root: Path,
    materialized_ids: set[str],
    reserved_ids: set[str],
    anchor_e: float,
    anchor_n: float,
) -> dict[str, Any]:
    forbidden = set(materialized_ids) | set(reserved_ids)
    seeds: list[dict[str, Any]] = []

    for zone in zones_for_wave(catalog, wave):
        zone_id = str(zone.get("id", "")).strip()
        if not zone_id:
            raise ValueError("zone is missing id")
        grid_path = grid_root / f"{zone_id}.json"
        if not grid_path.exists():
            raise ValueError(f"zone grid is missing: {grid_path}")
        grid = load_manifest(grid_path)
        selected = select_seed(
            grid,
            anchor_e,
            anchor_n,
            excluded_cell_ids=forbidden,
        )
        cell_id = str(selected["id"])
        forbidden.add(cell_id)
        seeds.append(
            {
                "zone_id": zone_id,
                "zone_name": str(zone.get("name", zone_id)),
                "wave": wave,
                "priority": int(zone.get("priority", 9999)),
                "cell_id": cell_id,
                "bbox": selected["bbox"],
                "distance_m": selected["seed_distance_m"],
                "excluded_existing_cell_ids": selected.get("excluded_existing_cell_ids", []),
            }
        )

    ids = [seed["cell_id"] for seed in seeds]
    if len(ids) != len(set(ids)):
        raise AssertionError("wave selector produced duplicate global cell IDs")

    return {
        "format": FORMAT,
        "crs": "EPSG:31370",
        "cell_size_m": 500,
        "wave": wave,
        "anchor": [anchor_e, anchor_n],
        "materialized_cell_count_before": len(materialized_ids),
        "reserved_cell_count": len(reserved_ids),
        "seed_count": len(seeds),
        "seeds": seeds,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Select one unique new global cell per Brussels wave zone")
    parser.add_argument("--wave", required=True)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--grid-root", type=Path, default=DEFAULT_GRID_ROOT)
    parser.add_argument("--existing-root", type=Path, default=DEFAULT_CELL_ROOT)
    parser.add_argument("--exclusions", type=Path, default=DEFAULT_EXCLUSIONS)
    parser.add_argument("--anchor-e", type=float, default=147868.29422791934)
    parser.add_argument("--anchor-n", type=float, default=169538.62414926197)
    parser.add_argument("--exclude-cell-id", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    materialized = load_existing_cell_ids(args.existing_root)
    reserved = load_excluded_ids(args.exclusions)
    reserved.update(str(cell_id) for cell_id in args.exclude_cell_id)
    result = select_wave_seeds(
        load_json(args.catalog),
        args.wave,
        args.grid_root,
        materialized,
        reserved,
        args.anchor_e,
        args.anchor_n,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{args.wave}: selected {result['seed_count']} unique new cells")
    for seed in result["seeds"]:
        print(f"  {seed['zone_id']}: {seed['cell_id']} ({seed['distance_m']} m)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
