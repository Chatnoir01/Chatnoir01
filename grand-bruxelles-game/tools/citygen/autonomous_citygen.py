#!/usr/bin/env python3
"""Deterministic, fail-closed scheduler for autonomous Brussels reconstruction.

The scheduler never promotes runtime geometry. It inventories authoritative source
cells already present in the repository, resumes from a durable state file, and
emits the next QA/generation batch. Missing or inconsistent evidence is
quarantined instead of guessed.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-autonomous-citygen-v1"
TERMINAL = {"RUNTIME_READY", "QUARANTINE"}


def _read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"expected object: {path}")
    return value


def discover_cells(source_root: Path) -> list[str]:
    if not source_root.exists():
        return []
    return sorted(
        child.name
        for child in source_root.iterdir()
        if child.is_dir() and child.name.startswith("bxl-")
    )


def load_state(path: Path | None) -> dict[str, Any]:
    if path is None or not path.exists():
        return {"format": FORMAT, "run_number": 0, "cells": {}}
    state = _read_json(path)
    if state.get("format") != FORMAT:
        raise ValueError("unsupported autonomous CityGen state format")
    if not isinstance(state.get("cells"), dict):
        raise ValueError("state cells must be an object")
    return state


def classify_cell(cell_id: str, source_root: Path, maturity_root: Path) -> tuple[str, list[str]]:
    source_manifest = source_root / cell_id / "manifest.json"
    if not source_manifest.exists():
        return "QUARANTINE", ["missing_authoritative_source_manifest"]
    try:
        source = _read_json(source_manifest)
    except (OSError, ValueError, json.JSONDecodeError):
        return "QUARANTINE", ["invalid_authoritative_source_manifest"]

    # A source manifest must contain some explicit feature/layer evidence. We do
    # not infer geometry from an empty JSON object.
    if not source:
        return "QUARANTINE", ["empty_authoritative_source_manifest"]

    maturity_path = maturity_root / f"{cell_id}.json"
    if not maturity_path.exists():
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
    required = ("runtime_geometry", "collisions", "streaming", "terrain", "heights", "photo_match", "performance")
    if all(gates.get(name) is True for name in required):
        return "RUNTIME_READY", []

    blockers = [name for name in required if gates.get(name) is not True]
    return "DATA_READY", blockers


def select_batch(cells: list[dict[str, Any]], batch_size: int) -> list[str]:
    priority = {"DISCOVERED": 0, "DATA_READY": 1}
    candidates = [cell for cell in cells if cell["state"] not in TERMINAL]
    candidates.sort(key=lambda cell: (priority.get(cell["state"], 99), cell["cell_id"]))
    return [cell["cell_id"] for cell in candidates[:batch_size]]


def run(source_root: Path, maturity_root: Path, state_path: Path | None, output_dir: Path, batch_size: int) -> dict[str, Any]:
    previous = load_state(state_path)
    discovered = discover_cells(source_root)
    cells: list[dict[str, Any]] = []
    counts: dict[str, int] = {}

    for cell_id in discovered:
        state, blockers = classify_cell(cell_id, source_root, maturity_root)
        previous_cell = previous.get("cells", {}).get(cell_id, {})
        cells.append({
            "cell_id": cell_id,
            "state": state,
            "blockers": blockers,
            "attempts": int(previous_cell.get("attempts", 0)),
        })
        counts[state] = counts.get(state, 0) + 1

    batch = select_batch(cells, batch_size)
    batch_set = set(batch)
    for cell in cells:
        if cell["cell_id"] in batch_set:
            cell["attempts"] += 1

    run_number = int(previous.get("run_number", 0)) + 1
    report = {
        "format": FORMAT,
        "run_number": run_number,
        "source_cell_count": len(discovered),
        "counts": dict(sorted(counts.items())),
        "selected_batch": batch,
        "cells": cells,
        "policy": {
            "crs": "EPSG:31370",
            "batch_size": batch_size,
            "runtime_promotion": "forbidden_without_all_required_gates",
            "uncertain_evidence": "quarantine_or_keep_pending_never_guess",
        },
    }

    state = {
        "format": FORMAT,
        "run_number": run_number,
        "cells": {cell["cell_id"]: {"state": cell["state"], "attempts": cell["attempts"]} for cell in cells},
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "autonomous_citygen_report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (output_dir / "autonomous_citygen_state.json").write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (output_dir / "worklist.txt").write_text("".join(f"{cell_id}\n" for cell_id in batch), encoding="utf-8")
    print(f"AUTONOMOUS_CITYGEN_OK run={run_number} source_cells={len(discovered)} selected={len(batch)} counts={report['counts']}")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--maturity-root", type=Path, required=True)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=4)
    args = parser.parse_args()
    if args.batch_size < 1 or args.batch_size > 32:
        raise SystemExit("batch size must be between 1 and 32")
    run(args.source_root, args.maturity_root, args.state, args.output_dir, args.batch_size)


if __name__ == "__main__":
    main()
