#!/usr/bin/env python3
"""Deterministic, fail-closed scheduler for autonomous Brussels reconstruction."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from bootstrap_cell_maturity import GATES as MATURITY_GATES

FORMAT = "grand-bruxelles-autonomous-citygen-v1"
TARGET_FORMAT = "grand-bruxelles-regional-target-grid-v1"
TERMINAL = {"RUNTIME_READY", "QUARANTINE"}
MANUAL_FRONTIER_ACTION = "secondary_height_validation_and_terrain_runtime_checks"
EVIDENCE_STAGES = (
    ("elevation_requirements.json", "derive_elevation_requirements"),
    ("elevation_dsm_resolution.json", "resolve_dsm_source"),
    ("elevation_dtm_resolution.json", "resolve_dtm_source"),
    ("elevation_dsm_archive_validation.json", "validate_dsm_archive"),
    ("elevation_dtm_archive_validation.json", "validate_dtm_archive"),
    ("elevation_raster_validation.json", "validate_dsm_dtm_georasters"),
    ("elevation_value_evidence.json", "assess_elevation_values"),
    ("elevation_candidate_frontier.json", "derive_elevation_candidate_frontier"),
    ("building_height_candidates.json", "derive_building_height_candidates"),
    ("terrain_lod_evidence.json", "evaluate_terrain_lod"),
)


def _read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"expected object: {path}")
    return value


def discover_cells(source_root: Path) -> list[str]:
    if not source_root.exists():
        return []
    return sorted(child.name for child in source_root.iterdir() if child.is_dir() and child.name.startswith("bxl-"))


def load_state(path: Path | None) -> dict[str, Any]:
    if path is None or not path.exists():
        return {"format": FORMAT, "run_number": 0, "cells": {}}
    state = _read_json(path)
    if state.get("format") != FORMAT or not isinstance(state.get("cells"), dict):
        raise ValueError("unsupported autonomous CityGen state format")
    return state


def load_target_grid(path: Path | None) -> dict[str, dict[str, Any]]:
    if path is None:
        return {}
    payload = _read_json(path)
    if payload.get("format") != TARGET_FORMAT or payload.get("crs") != "EPSG:31370":
        raise ValueError("unsupported regional target grid or CRS")
    out: dict[str, dict[str, Any]] = {}
    for row in payload.get("cells") or []:
        if not isinstance(row, dict):
            raise ValueError("target grid cells must be objects")
        cell_id = row.get("cell_id")
        bbox = row.get("bbox")
        if not isinstance(cell_id, str) or not cell_id.startswith("bxl-") or cell_id in out:
            raise ValueError("target grid contains invalid or duplicate cell id")
        if not isinstance(bbox, list) or len(bbox) != 4 or not all(isinstance(v, (int, float)) for v in bbox):
            raise ValueError(f"target grid cell has invalid bbox: {cell_id}")
        if not (bbox[0] < bbox[2] and bbox[1] < bbox[3]) or min(bbox) < 10_000:
            raise ValueError(f"target grid cell bbox is not valid EPSG:31370: {cell_id}")
        out[cell_id] = {
            "bbox": [float(v) if not float(v).is_integer() else int(v) for v in bbox],
            "municipalities": sorted(str(v) for v in (row.get("municipalities") or [])),
        }
    if not out:
        raise ValueError("regional target grid contains no cells")
    return out


def _maturity_path(cell_id: str, source_root: Path, maturity_root: Path) -> Path | None:
    committed = maturity_root / f"{cell_id}.json"
    if committed.exists():
        return committed
    sidecar = source_root / cell_id / "maturity.json"
    return sidecar if sidecar.exists() else None


def _missing_declared_source_files(source: dict[str, Any], cell_dir: Path) -> list[str]:
    """Return manifest-declared layer files that are physically absent.

    Legacy synthetic/list-style manifests remain supported; only explicit file
    contracts are enforced. This lets CityGen rematerialize a durable cell whose
    manifest survived while one or more authoritative source payloads did not.
    """
    layers = source.get("layers")
    if not isinstance(layers, dict):
        return []
    missing: list[str] = []
    for layer_name, spec in sorted(layers.items()):
        if not isinstance(spec, dict):
            continue
        declared = spec.get("file")
        if not isinstance(declared, str) or not declared.strip():
            continue
        relative = Path(declared)
        if relative.is_absolute() or ".." in relative.parts:
            missing.append(f"{layer_name}:{declared}")
            continue
        if not (cell_dir / relative).is_file():
            missing.append(f"{layer_name}:{declared}")
    return missing


def evidence_plan(cell_id: str, source_root: Path) -> tuple[int, str]:
    cell_dir = source_root / cell_id
    completed = 0
    for filename, action in EVIDENCE_STAGES:
        if not (cell_dir / filename).exists():
            return completed, action
        completed += 1
    return completed, MANUAL_FRONTIER_ACTION


def classify_cell(cell_id: str, source_root: Path, maturity_root: Path) -> tuple[str, list[str]]:
    cell_dir = source_root / cell_id
    source_manifest = cell_dir / "manifest.json"
    if not source_manifest.exists():
        return "QUARANTINE", ["missing_authoritative_source_manifest"]
    try:
        source = _read_json(source_manifest)
    except (OSError, ValueError, json.JSONDecodeError):
        return "QUARANTINE", ["invalid_authoritative_source_manifest"]
    if not source:
        return "QUARANTINE", ["empty_authoritative_source_manifest"]
    if source.get("cell_id") not in (None, cell_id):
        return "QUARANTINE", ["authoritative_source_identity_mismatch"]
    if source.get("crs") not in (None, "EPSG:31370"):
        return "QUARANTINE", ["authoritative_source_crs_mismatch"]
    missing_files = _missing_declared_source_files(source, cell_dir)
    if missing_files:
        return "MISSING_SOURCE", [f"missing_authoritative_source_file:{item}" for item in missing_files]

    maturity_path = _maturity_path(cell_id, source_root, maturity_root)
    if maturity_path is None:
        return "DISCOVERED", ["maturity_manifest_missing"]
    try:
        maturity = _read_json(maturity_path)
    except (OSError, ValueError, json.JSONDecodeError):
        return "QUARANTINE", ["invalid_maturity_manifest"]
    if maturity.get("cell_id") != cell_id or maturity.get("crs") != "EPSG:31370":
        return "QUARANTINE", ["maturity_identity_or_crs_mismatch"]
    geometry = maturity.get("geometry", {})
    if not geometry.get("authoritative_geometry_ready", False):
        return "QUARANTINE", ["authoritative_geometry_not_ready"]
    gates = maturity.get("maturity", {}).get("gates", {})
    if all(gates.get(name) is True for name in MATURITY_GATES):
        return "RUNTIME_READY", []
    return "DATA_READY", [name for name in MATURITY_GATES if gates.get(name) is not True]


def _autonomously_actionable(cell: dict[str, Any]) -> bool:
    if cell["state"] in TERMINAL:
        return False
    if cell["state"] == "DATA_READY" and int(cell.get("evidence_progress", 0)) >= len(EVIDENCE_STAGES):
        return False
    return True


def _selection_priority(cell: dict[str, Any]) -> int:
    # A source directory with a surviving manifest but a missing declared payload
    # is repair work, not regional expansion. Repair it before advancing ordinary
    # evidence so stale source/elevation state cannot persist indefinitely.
    if cell.get("state") == "MISSING_SOURCE" and any(
        str(blocker).startswith("missing_authoritative_source_file:")
        for blocker in (cell.get("blockers") or [])
    ):
        return -1
    return {"DATA_READY": 0, "DISCOVERED": 1, "MISSING_SOURCE": 2}.get(str(cell.get("state")), 99)


def select_batch(cells: list[dict[str, Any]], batch_size: int) -> list[str]:
    # Finish already-materialized source cells before expanding regional coverage,
    # but repair physically incomplete source cells first.
    candidates = [cell for cell in cells if _autonomously_actionable(cell)]
    candidates.sort(key=lambda cell: (
        _selection_priority(cell),
        -int(cell.get("evidence_progress", 0)) if cell["state"] == "DATA_READY" else 0,
        int(cell.get("attempts", 0)),
        cell["cell_id"],
    ))
    return [cell["cell_id"] for cell in candidates[:batch_size]]


def run(
    source_root: Path,
    maturity_root: Path,
    state_path: Path | None,
    output_dir: Path,
    batch_size: int,
    target_grid_path: Path | None = None,
    refresh_only: bool = False,
) -> dict[str, Any]:
    previous = load_state(state_path)
    source_cells = discover_cells(source_root)
    source_set = set(source_cells)
    target = load_target_grid(target_grid_path)
    cell_ids = sorted(set(target) | source_set) if target else source_cells
    cells: list[dict[str, Any]] = []
    counts: dict[str, int] = {}
    for cell_id in cell_ids:
        target_row = target.get(cell_id)
        if target and target_row is None:
            state, blockers = "QUARANTINE", ["source_cell_outside_regional_target_grid"]
        elif cell_id not in source_set:
            state, blockers = "MISSING_SOURCE", ["authoritative_source_cell_missing"]
        else:
            state, blockers = classify_cell(cell_id, source_root, maturity_root)
        previous_cell = previous.get("cells", {}).get(cell_id, {})
        if state == "MISSING_SOURCE":
            progress, next_action = 0, "materialize_authoritative_source"
        elif cell_id in source_set:
            progress, next_action = evidence_plan(cell_id, source_root)
        else:
            progress, next_action = 0, "materialize_authoritative_source"
        row = {
            "cell_id": cell_id,
            "state": state,
            "blockers": blockers,
            "attempts": int(previous_cell.get("attempts", 0)),
            "evidence_progress": progress,
            "evidence_stage_count": len(EVIDENCE_STAGES),
            "next_action": next_action,
        }
        row["autonomous_actionable"] = _autonomously_actionable(row)
        if target_row is not None:
            row["bbox"] = target_row["bbox"]
            row["municipalities"] = target_row["municipalities"]
        cells.append(row)
        counts[state] = counts.get(state, 0) + 1

    batch = [] if refresh_only else select_batch(cells, batch_size)
    batch_set = set(batch)
    if not refresh_only:
        for cell in cells:
            if cell["cell_id"] in batch_set:
                cell["attempts"] += 1
    run_number = int(previous.get("run_number", 0)) if refresh_only else int(previous.get("run_number", 0)) + 1
    report = {
        "format": FORMAT,
        "run_number": run_number,
        "source_cell_count": len(source_cells),
        "target_cell_count": len(target) if target else len(source_cells),
        "counts": dict(sorted(counts.items())),
        "selected_batch": batch,
        "refresh_only": refresh_only,
        "cells": cells,
        "policy": {
            "crs": "EPSG:31370",
            "batch_size": batch_size,
            "maturity_gate_count": len(MATURITY_GATES),
            "runtime_promotion": "forbidden_without_full_regional_maturity_contract",
            "uncertain_evidence": "quarantine_or_keep_pending_never_guess",
            "incomplete_source_priority": "repair_declared_source_payloads_before_evidence_or_regional_expansion",
            "missing_source_priority": "expand_only_after_existing_source_cells_reach_their_current_autonomous_frontier",
            "data_ready_priority": "finish_most_advanced_autonomous_evidence_frontier_before_materializing_more_source_cells",
            "manual_frontier": "exclude_from_autonomous_batches_until_secondary_height_and_terrain_runtime_checks_are_implemented",
            "refresh_only": "recompute durable classification_and_evidence_progress_without_new_attempts_or_batch_selection",
        },
    }
    state = {
        "format": FORMAT,
        "run_number": run_number,
        "cells": {
            cell["cell_id"]: {
                "state": cell["state"],
                "attempts": cell["attempts"],
                "evidence_progress": cell["evidence_progress"],
                "next_action": cell["next_action"],
            }
            for cell in cells
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "autonomous_citygen_report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (output_dir / "autonomous_citygen_state.json").write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (output_dir / "worklist.txt").write_text("".join(f"{cell_id}\n" for cell_id in batch), encoding="utf-8")
    mode = "refresh" if refresh_only else "schedule"
    print(f"AUTONOMOUS_CITYGEN_OK mode={mode} run={run_number} source_cells={len(source_cells)} target_cells={report['target_cell_count']} selected={len(batch)} counts={report['counts']}")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--maturity-root", type=Path, required=True)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--target-grid", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument(
        "--refresh-only",
        action="store_true",
        help="recompute classification/evidence progress without incrementing scheduler run or attempts",
    )
    args = parser.parse_args()
    if args.batch_size < 1 or args.batch_size > 32:
        raise SystemExit("batch size must be between 1 and 32")
    run(
        args.source_root,
        args.maturity_root,
        args.state,
        args.output_dir,
        args.batch_size,
        args.target_grid,
        refresh_only=args.refresh_only,
    )


if __name__ == "__main__":
    main()
