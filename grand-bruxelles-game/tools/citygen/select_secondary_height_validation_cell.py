#!/usr/bin/env python3
"""Select one durable CityGen cell for independent secondary-height validation.

Selection is deliberately fail-closed. A target must be a fully evidenced DATA_READY
cell owned only by the requested municipality, already present in the durable source
cache, and explicitly waiting for secondary-height / terrain checks. The selector
never authorizes runtime geometry, heights, terrain or promotion.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-citygen-secondary-height-target-v1"
TARGET_NEXT_ACTION = "secondary_height_validation_and_terrain_runtime_checks"
CELL_RE = re.compile(r"^bxl-e(\d+)-n(\d+)-s500$")


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _available_cells(path: Path) -> set[str]:
    cells = {line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()}
    if not cells:
        raise ValueError("durable source-cell inventory is empty")
    for cell_id in cells:
        if CELL_RE.fullmatch(cell_id) is None:
            raise ValueError(f"invalid durable source cell id: {cell_id!r}")
    return cells


def _bbox_for(cell: dict[str, Any], cell_id: str) -> list[int]:
    raw = cell.get("bbox")
    if not isinstance(raw, list) or len(raw) != 4:
        raise ValueError(f"eligible cell has invalid bbox: {cell_id}")
    try:
        bbox = [int(value) for value in raw]
    except (TypeError, ValueError) as exc:
        raise ValueError(f"eligible cell has non-numeric bbox: {cell_id}") from exc
    match = CELL_RE.fullmatch(cell_id)
    assert match is not None
    east = int(match.group(1))
    north = int(match.group(2))
    expected = [east, north, east + 500, north + 500]
    if bbox != expected:
        raise ValueError(f"eligible cell bbox does not match its 500m identity: {cell_id}")
    return bbox


def select(report: dict[str, Any], available: set[str], municipality: str) -> dict[str, Any]:
    municipality = municipality.strip().casefold()
    if not municipality:
        raise ValueError("municipality is required")
    cells = report.get("cells")
    if not isinstance(cells, list):
        raise ValueError("autonomous CityGen report is missing cells")

    eligible: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in cells:
        if not isinstance(raw, dict):
            raise ValueError("autonomous CityGen report contains a non-object cell")
        cell_id = str(raw.get("cell_id") or "").strip()
        if not cell_id:
            raise ValueError("autonomous CityGen report contains a cell without identity")
        if cell_id in seen:
            raise ValueError(f"duplicate cell in autonomous CityGen report: {cell_id}")
        seen.add(cell_id)

        municipalities_raw = raw.get("municipalities")
        if not isinstance(municipalities_raw, list):
            continue
        municipalities = sorted({str(value).strip().casefold() for value in municipalities_raw if str(value).strip()})
        # This workflow downloads one municipality package. Boundary cells are not
        # eligible because a single-package comparison would be incomplete.
        if municipalities != [municipality]:
            continue
        if raw.get("state") != "DATA_READY":
            continue
        if raw.get("autonomous_actionable") is not False:
            continue
        if raw.get("next_action") != TARGET_NEXT_ACTION:
            continue
        try:
            progress = int(raw.get("evidence_progress"))
            stage_count = int(raw.get("evidence_stage_count"))
        except (TypeError, ValueError):
            continue
        if stage_count <= 0 or progress != stage_count:
            continue
        if cell_id not in available:
            continue
        bbox = _bbox_for(raw, cell_id)
        eligible.append({
            "cell_id": cell_id,
            "bbox_epsg31370": bbox,
            "municipality": municipality,
            "evidence_progress": progress,
            "evidence_stage_count": stage_count,
            "next_action": TARGET_NEXT_ACTION,
        })

    if not eligible:
        raise ValueError(
            f"no durable fully-evidenced {municipality} cell is ready for secondary-height validation"
        )
    chosen = sorted(eligible, key=lambda row: row["cell_id"])[0]
    return {
        "format": FORMAT,
        **chosen,
        "eligible_cell_count": len(eligible),
        "selection_policy": "lexicographically_first_fully_evidenced_single_municipality_durable_cell",
        "runtime_promotion_allowed": False,
        "runtime_approved": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--available-cells", type=Path, required=True)
    parser.add_argument("--municipality", default="anderlecht")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = select(_read_json(args.report), _available_cells(args.available_cells), args.municipality)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "CITYGEN_SECONDARY_HEIGHT_TARGET_OK",
        result["cell_id"],
        f"municipality={result['municipality']}",
        f"eligible={result['eligible_cell_count']}",
        "runtime_promotion=false",
    )


if __name__ == "__main__":
    main()
