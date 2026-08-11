#!/usr/bin/env python3
"""Select one central, globally unique seed for every still-uncovered municipality.

Coverage is read from the project's measured coverage report. A zone is eligible
only when its official 500 m grid exists and its materialized cell count is zero.
The anchor is the center of the official boundary bbox recorded in the v2 grid,
not the global Midi anchor; this avoids filling only municipal edge cells.
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

FORMAT = "grand-bruxelles-wave-seeds-v1"
DEFAULT_CATALOG = ROOT / "data" / "remaining_brussels_zones.json"
DEFAULT_COVERAGE = ROOT / "data" / "processed" / "remaining_brussels" / "coverage_report.json"
DEFAULT_GRID_ROOT = ROOT / "data" / "processed" / "remaining_brussels" / "cells"
DEFAULT_CELL_ROOT = ROOT / "data" / "urbis" / "remaining_brussels" / "cells"
DEFAULT_RUNTIME_EXCLUSIONS = ROOT / "data" / "urbis" / "remaining_brussels" / "runtime_exclusions.json"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def reservation_ids(path: Path | None) -> set[str]:
    if path is None or not path.exists():
        return set()
    payload = load_json(path)
    values = payload.get("reserved_cell_ids")
    if isinstance(values, list):
        return {str(value) for value in values if str(value).startswith("bxl-e")}
    entries = payload.get("excluded_cells")
    if isinstance(entries, list):
        return {
            str(entry.get("cell_id"))
            for entry in entries
            if isinstance(entry, dict) and str(entry.get("cell_id", "")).startswith("bxl-e")
        }
    raise ValueError(f"reservation file has no supported cell list: {path}")


def grid_center(grid: dict[str, Any]) -> tuple[float, float]:
    bbox = grid.get("source_bbox")
    if not isinstance(bbox, list) or len(bbox) != 4:
        # Older v2 manifests should still have deterministic cells. Derive a
        # conservative envelope from those exact grid bboxes if needed.
        cells = grid.get("cells", [])
        boxes = [cell.get("bbox") for cell in cells if isinstance(cell, dict)]
        boxes = [box for box in boxes if isinstance(box, list) and len(box) == 4]
        if not boxes:
            raise ValueError("grid has neither source_bbox nor valid cell bboxes")
        bbox = [
            min(float(box[0]) for box in boxes),
            min(float(box[1]) for box in boxes),
            max(float(box[2]) for box in boxes),
            max(float(box[3]) for box in boxes),
        ]
    min_e, min_n, max_e, max_n = [float(value) for value in bbox]
    return (min_e + max_e) * 0.5, (min_n + max_n) * 0.5


def select_uncovered(
    catalog: dict[str, Any],
    coverage: dict[str, Any],
    grid_root: Path,
    existing_ids: set[str],
    reserved_ids: set[str],
    only_zone_ids: set[str] | None = None,
) -> dict[str, Any]:
    coverage_zones = {
        str(item.get("zone_id")): item
        for item in coverage.get("zones", [])
        if isinstance(item, dict)
    }
    catalog_zones = [zone for zone in catalog.get("zones", []) if isinstance(zone, dict)]
    catalog_zones.sort(key=lambda zone: (int(zone.get("priority", 9999)), str(zone.get("id", ""))))

    forbidden = set(existing_ids) | set(reserved_ids)
    seeds: list[dict[str, Any]] = []
    skipped_covered: list[str] = []

    for zone in catalog_zones:
        zone_id = str(zone.get("id", "")).strip()
        if not zone_id:
            continue
        if only_zone_ids and zone_id not in only_zone_ids:
            continue
        measured = coverage_zones.get(zone_id)
        if measured is None:
            raise ValueError(f"coverage report missing catalog zone {zone_id}")
        if not bool(measured.get("grid_ready")):
            raise ValueError(f"official grid not ready for {zone_id}")
        if int(measured.get("materialized_cells", 0)) > 0:
            skipped_covered.append(zone_id)
            continue

        grid = load_manifest(grid_root / f"{zone_id}.json")
        anchor_e, anchor_n = grid_center(grid)
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
                "wave": str(zone.get("wave", "")),
                "priority": int(zone.get("priority", 9999)),
                "cell_id": cell_id,
                "bbox": selected["bbox"],
                "distance_m": selected["seed_distance_m"],
                "anchor": [anchor_e, anchor_n],
                "anchor_kind": "official_boundary_bbox_center",
            }
        )

    ids = [seed["cell_id"] for seed in seeds]
    if len(ids) != len(set(ids)):
        raise AssertionError("uncovered-zone selector produced duplicate global cell IDs")

    return {
        "format": FORMAT,
        "crs": "EPSG:31370",
        "cell_size_m": 500,
        "wave": "GAP-FILL",
        "selection": "zero_materialized_zones_boundary_center",
        "materialized_cell_count_before": len(existing_ids),
        "reserved_cell_count": len(reserved_ids),
        "seed_count": len(seeds),
        "skipped_already_covered_zone_ids": skipped_covered,
        "seeds": seeds,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Select central seeds for municipality grids with zero materialized cells")
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--coverage", type=Path, default=DEFAULT_COVERAGE)
    parser.add_argument("--grid-root", type=Path, default=DEFAULT_GRID_ROOT)
    parser.add_argument("--existing-root", type=Path, default=DEFAULT_CELL_ROOT)
    parser.add_argument("--runtime-exclusions", type=Path, default=DEFAULT_RUNTIME_EXCLUSIONS)
    parser.add_argument("--reservation-file", type=Path, action="append", default=[])
    parser.add_argument("--zone-id", action="append", default=[])
    parser.add_argument("--exclude-cell-id", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    reserved = reservation_ids(args.runtime_exclusions)
    for path in args.reservation_file:
        reserved.update(reservation_ids(path))
    reserved.update(str(cell_id) for cell_id in args.exclude_cell_id)

    result = select_uncovered(
        load_json(args.catalog),
        load_json(args.coverage),
        args.grid_root,
        load_existing_cell_ids(args.existing_root),
        reserved,
        set(args.zone_id) if args.zone_id else None,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"gap-fill: {result['seed_count']} uncovered municipality seeds selected")
    for seed in result["seeds"]:
        print(f"  {seed['zone_id']}: {seed['cell_id']} ({seed['distance_m']} m from boundary center)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
