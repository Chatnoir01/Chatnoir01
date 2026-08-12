#!/usr/bin/env python3
"""Measure coverage of Brussels City subzones owned by this workstream.

The report is independent from the 17-municipality coverage report because the
City of Brussels is split across workstreams. Global 500 m cells are counted
once even when two named subzones overlap. Laeken is reservation-only and is
therefore reported separately, never as production coverage for this branch.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GRID_ROOT = ROOT / "data" / "processed" / "brussels_city_remaining" / "cells"
DEFAULT_CELL_ROOT = ROOT / "data" / "urbis" / "remaining_brussels" / "cells"
DEFAULT_RUNTIME_INDEX = ROOT / "data" / "urbis" / "remaining_brussels" / "runtime_index.json"
FORMAT = "grand-bruxelles-city-remaining-coverage-v1"
PRODUCTION_SUBZONES = (
    ("haren", "Haren", "haren.json"),
    ("neder-over-heembeek", "Neder-over-Heembeek", "neder-over-heembeek.json"),
    ("quartier-europeen", "Quartier Européen", "quartier-europeen.json"),
    ("louise", "Louise", "louise.json"),
    ("roosevelt", "Roosevelt", "roosevelt.json"),
    ("bois-de-la-cambre", "Bois de la Cambre", "bois-de-la-cambre.json"),
)
RESERVATION_GRID = ("laeken", "Laeken", "laeken-reservation.json")


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def global_cell_ids_from_grid(path: Path) -> set[str]:
    payload = load_json(path)
    if payload.get("format") != "grand-bruxelles-zone-cells-v2":
        raise ValueError(f"unsupported zone grid: {path}")
    ids = {
        str(cell.get("id"))
        for cell in payload.get("cells", [])
        if isinstance(cell, dict) and str(cell.get("id", "")).startswith("bxl-e")
    }
    if len(ids) != int(payload.get("cell_count", len(ids))):
        raise ValueError(f"global cell ID count mismatch in {path}")
    return ids


def materialized_ids(root: Path) -> set[str]:
    result: set[str] = set()
    for manifest_path in sorted(root.glob("*/manifest.json")):
        payload = load_json(manifest_path)
        if payload.get("format") != "grand-bruxelles-urbis-built-cell-v1":
            raise ValueError(f"unsupported built-cell manifest: {manifest_path}")
        cell_id = str(payload.get("cell_id", ""))
        if cell_id:
            result.add(cell_id)
    return result


def build_report(grid_root: Path, cell_root: Path, runtime_index_path: Path | None) -> dict[str, Any]:
    built = materialized_ids(cell_root)
    planned_union: set[str] = set()
    memberships: dict[str, set[str]] = {}
    subzones: list[dict[str, Any]] = []
    for subzone_id, name, filename in PRODUCTION_SUBZONES:
        path = grid_root / filename
        if not path.exists():
            subzones.append({
                "subzone_id": subzone_id,
                "name": name,
                "grid_ready": False,
                "planned_cells": 0,
                "materialized_cells": 0,
                "coverage_percent": 0.0,
                "materialized_cell_ids": [],
            })
            continue
        ids = global_cell_ids_from_grid(path)
        built_here = sorted(ids & built)
        planned_union.update(ids)
        for cell_id in ids:
            memberships.setdefault(cell_id, set()).add(subzone_id)
        subzones.append({
            "subzone_id": subzone_id,
            "name": name,
            "grid_ready": True,
            "planned_cells": len(ids),
            "materialized_cells": len(built_here),
            "coverage_percent": round((len(built_here) / len(ids) * 100.0) if ids else 0.0, 2),
            "materialized_cell_ids": built_here,
        })

    reservation_id, reservation_name, reservation_file = RESERVATION_GRID
    reservation_path = grid_root / reservation_file
    reservation_ids = global_cell_ids_from_grid(reservation_path) if reservation_path.exists() else set()
    built_in_union = built & planned_union
    shared = {cell_id: sorted(values) for cell_id, values in memberships.items() if len(values) > 1}
    result: dict[str, Any] = {
        "format": FORMAT,
        "crs": "EPSG:31370",
        "cell_size_m": 500,
        "production_subzones_total": len(PRODUCTION_SUBZONES),
        "production_subzone_grids_ready": sum(1 for item in subzones if item["grid_ready"]),
        "production_subzones_with_materialized_cell": sum(1 for item in subzones if item["materialized_cells"] > 0),
        "unique_planned_production_cells": len(planned_union),
        "materialized_production_cells": len(built_in_union),
        "production_grid_coverage_percent": round((len(built_in_union) / len(planned_union) * 100.0) if planned_union else 0.0, 2),
        "cross_subzone_shared_cell_count": len(shared),
        "cross_subzone_shared_cells": shared,
        "subzones": subzones,
        "reservation_only": {
            "subzone_id": reservation_id,
            "name": reservation_name,
            "grid_ready": reservation_path.exists(),
            "reserved_cells": len(reservation_ids),
            "materialized_by_this_branch": sorted(reservation_ids & built),
        },
        "known_remaining_scope": {
            "covered_by_named_subzone_grids": [item["subzone_id"] for item in subzones if item["grid_ready"]],
            "reservation_only": [reservation_id],
            "still_requires_separate_polygon_or_ownership_difference": ["pentagon-outside-main-corridor"],
        },
    }
    if runtime_index_path and runtime_index_path.exists():
        index = load_json(runtime_index_path)
        result["runtime"] = {
            "format": index.get("format"),
            "streamable_cells_total": int(index.get("cell_count", len(index.get("cells", [])))),
        }
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Build measured coverage report for remaining Brussels City subzones")
    parser.add_argument("--grid-root", type=Path, default=DEFAULT_GRID_ROOT)
    parser.add_argument("--cell-root", type=Path, default=DEFAULT_CELL_ROOT)
    parser.add_argument("--runtime-index", type=Path, default=DEFAULT_RUNTIME_INDEX)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = build_report(args.grid_root, args.cell_root, args.runtime_index)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"City remaining: {report['production_subzone_grids_ready']}/{report['production_subzones_total']} grids, "
        f"{report['production_subzones_with_materialized_cell']} subzones seeded, "
        f"{report['materialized_production_cells']}/{report['unique_planned_production_cells']} unique cells materialized"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
