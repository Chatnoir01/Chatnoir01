#!/usr/bin/env python3
"""Measure official-grid and materialized-cell coverage for remaining Brussels.

The report distinguishes municipal planning coverage from globally unique game
cells. Because the same 500 m Lambert72 cell can intersect multiple communes,
municipal percentages must not be summed to obtain global progress.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "data" / "remaining_brussels_zones.json"
DEFAULT_GRID_ROOT = ROOT / "data" / "processed" / "remaining_brussels" / "cells"
DEFAULT_CELL_ROOT = ROOT / "data" / "urbis" / "remaining_brussels" / "cells"
DEFAULT_INDEX = ROOT / "data" / "urbis" / "remaining_brussels" / "runtime_index.json"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_materialized_ids(root: Path) -> set[str]:
    ids: set[str] = set()
    if not root.exists():
        return ids
    for manifest_path in sorted(root.glob("*/manifest.json")):
        payload = load_json(manifest_path)
        if payload.get("format") != "grand-bruxelles-urbis-built-cell-v1":
            raise ValueError(f"unsupported built-cell manifest: {manifest_path}")
        cell_id = str(payload.get("cell_id", "")).strip()
        if not cell_id:
            raise ValueError(f"missing cell_id in {manifest_path}")
        ids.add(cell_id)
    return ids


def load_zone_grid(path: Path) -> dict[str, Any]:
    payload = load_json(path)
    if payload.get("format") != "grand-bruxelles-zone-cells-v2":
        raise ValueError(f"unsupported zone-cell manifest: {path}")
    cells = payload.get("cells")
    if not isinstance(cells, list):
        raise ValueError(f"zone-cell manifest has no cells list: {path}")
    return payload


def zone_report(zone: dict[str, Any], grid_root: Path, materialized_ids: set[str]) -> dict[str, Any]:
    zone_id = str(zone["id"])
    grid_path = grid_root / f"{zone_id}.json"
    base = {
        "zone_id": zone_id,
        "name": str(zone.get("name", zone_id)),
        "wave": str(zone.get("wave", "")),
        "priority": int(zone.get("priority", 9999)),
        "grid_ready": grid_path.exists(),
        "planned_cells": 0,
        "materialized_cells": 0,
        "coverage_percent": 0.0,
        "materialized_cell_ids": [],
    }
    if not grid_path.exists():
        return base

    grid = load_zone_grid(grid_path)
    cell_ids = [str(cell["id"]) for cell in grid["cells"] if isinstance(cell, dict) and cell.get("id")]
    unique_ids = set(cell_ids)
    built = sorted(unique_ids & materialized_ids)
    count = len(unique_ids)
    base.update(
        {
            "planned_cells": count,
            "materialized_cells": len(built),
            "coverage_percent": round((len(built) / count * 100.0) if count else 0.0, 2),
            "materialized_cell_ids": built,
        }
    )
    return base


def build_report(
    catalog: dict[str, Any],
    grid_root: Path,
    cell_root: Path,
    runtime_index_path: Path | None = None,
) -> dict[str, Any]:
    zones = catalog.get("zones")
    if not isinstance(zones, list) or not zones:
        raise ValueError("catalog must contain a non-empty zones list")

    materialized_ids = load_materialized_ids(cell_root)
    zone_reports = [zone_report(zone, grid_root, materialized_ids) for zone in zones]
    zone_reports.sort(key=lambda item: (item["priority"], item["zone_id"]))

    planned_global_ids: set[str] = set()
    memberships: dict[str, list[str]] = {}
    for zone in zones:
        zone_id = str(zone["id"])
        path = grid_root / f"{zone_id}.json"
        if not path.exists():
            continue
        grid = load_zone_grid(path)
        for cell in grid["cells"]:
            if not isinstance(cell, dict) or not cell.get("id"):
                continue
            cell_id = str(cell["id"])
            planned_global_ids.add(cell_id)
            memberships.setdefault(cell_id, []).append(zone_id)

    runtime = None
    if runtime_index_path is not None and runtime_index_path.exists():
        runtime = load_json(runtime_index_path)
        if runtime.get("format") not in {
            "grand-bruxelles-urbis-runtime-index-v1",
            "grand-bruxelles-urbis-runtime-index-v2",
        }:
            raise ValueError(f"unsupported runtime index: {runtime_index_path}")

    materialized_in_planned = materialized_ids & planned_global_ids
    planned_count = len(planned_global_ids)
    shared_cells = {
        cell_id: sorted(zone_ids)
        for cell_id, zone_ids in memberships.items()
        if len(set(zone_ids)) > 1
    }
    result: dict[str, Any] = {
        "format": "grand-bruxelles-remaining-coverage-v1",
        "crs": "EPSG:31370",
        "cell_size_m": 500,
        "municipalities_total": len(zones),
        "municipality_grids_ready": sum(1 for zone in zone_reports if zone["grid_ready"]),
        "unique_planned_cells_known": planned_count,
        "materialized_cells_total": len(materialized_ids),
        "materialized_cells_in_known_grids": len(materialized_in_planned),
        "known_grid_coverage_percent": round(
            (len(materialized_in_planned) / planned_count * 100.0) if planned_count else 0.0,
            2,
        ),
        "shared_cross_municipality_cell_count": len(shared_cells),
        "shared_cross_municipality_cells": shared_cells,
        "zones": zone_reports,
    }
    if runtime is not None:
        result["runtime"] = {
            "format": runtime.get("format"),
            "streamable_cells": int(runtime.get("cell_count", len(runtime.get("cells", [])))),
            "excluded_cells": int(runtime.get("excluded_cell_count", 0)),
        }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a coverage report for remaining Brussels")
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--grid-root", type=Path, default=DEFAULT_GRID_ROOT)
    parser.add_argument("--cell-root", type=Path, default=DEFAULT_CELL_ROOT)
    parser.add_argument("--runtime-index", type=Path, default=DEFAULT_INDEX)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    report = build_report(
        load_json(args.catalog),
        args.grid_root,
        args.cell_root,
        args.runtime_index,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "coverage: "
        f"{report['municipality_grids_ready']}/{report['municipalities_total']} municipality grids, "
        f"{report['materialized_cells_in_known_grids']}/{report['unique_planned_cells_known']} known global cells"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
