#!/usr/bin/env python3
"""Advance Brussels DATA_READY cells into deterministic, candidate-only runtime bundles.

This frontier never authorizes a runtime mount or JOUABLE promotion. It only compiles
source-backed plan geometry and networks so already-matured regional data does not sit
idle while later collision/terrain/performance/photo-match gates remain pending.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import build_runtime_candidate_bundle as runtime_bundle

FORMAT = "grand-bruxelles-regional-runtime-candidate-frontier-v1"
STATE_FORMAT = "grand-bruxelles-autonomous-citygen-v1"
GRID_FORMAT = "grand-bruxelles-regional-target-grid-v1"
CANDIDATE_FORMAT = "grand-bruxelles-runtime-candidate-bundle-v1"
REGIONAL_MUNICIPALITY_TARGET = 19
ELIGIBLE_STATES = {"DATA_READY", "RUNTIME_READY"}


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected object: {path}")
    return value


def _grid_cells(path: Path) -> dict[str, list[str]]:
    payload = _read(path)
    if payload.get("format") != GRID_FORMAT or payload.get("crs") != "EPSG:31370":
        raise ValueError("unsupported Brussels regional target grid")
    out: dict[str, list[str]] = {}
    for row in payload.get("cells") or []:
        if not isinstance(row, dict):
            continue
        cell_id = row.get("cell_id")
        if not isinstance(cell_id, str):
            continue
        out[cell_id] = sorted({str(v).strip() for v in (row.get("municipalities") or []) if str(v).strip()})
    if not out:
        raise ValueError("regional target grid contains no cells")
    return out


def _already_compiled(existing_root: Path | None, cell_id: str) -> bool:
    if existing_root is None:
        return False
    path = existing_root / cell_id / "candidate.json"
    if not path.is_file():
        return False
    try:
        candidate = _read(path)
    except Exception:
        return False
    return candidate.get("format") == CANDIDATE_FORMAT and candidate.get("cell_id") == cell_id


def _priority(row: dict[str, Any]) -> tuple[Any, ...]:
    # RUNTIME_READY first, then highest evidence progress, then cells with fewer
    # scheduler attempts; cell id keeps selection deterministic.
    state_rank = 0 if row.get("state") == "RUNTIME_READY" else 1
    return (
        state_rank,
        -int(row.get("evidence_progress", 0)),
        int(row.get("attempts", 0)),
        str(row.get("cell_id")),
    )


def discover_candidates(
    source_root: Path,
    state_path: Path,
    target_grid_path: Path,
    existing_root: Path | None = None,
) -> list[dict[str, Any]]:
    state = _read(state_path)
    if state.get("format") != STATE_FORMAT or not isinstance(state.get("cells"), dict):
        raise ValueError("unsupported autonomous CityGen state")
    municipalities = _grid_cells(target_grid_path)
    rows: list[dict[str, Any]] = []
    for cell_id, raw in sorted(state["cells"].items()):
        if not isinstance(raw, dict) or raw.get("state") not in ELIGIBLE_STATES:
            continue
        if not (source_root / cell_id / "manifest.json").is_file():
            continue
        if _already_compiled(existing_root, cell_id):
            continue
        rows.append(
            {
                "cell_id": cell_id,
                "state": str(raw.get("state")),
                "evidence_progress": int(raw.get("evidence_progress", 0)),
                "attempts": int(raw.get("attempts", 0)),
                "municipalities": municipalities.get(cell_id, []),
            }
        )
    rows.sort(key=_priority)
    return rows


def select_batch(rows: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    if limit < 1:
        raise ValueError("limit must be >= 1")
    if limit < REGIONAL_MUNICIPALITY_TARGET:
        return rows[:limit]

    municipality_names = sorted({m for row in rows for m in row.get("municipalities", [])})
    if not municipality_names:
        return rows[:limit]

    selected: list[dict[str, Any]] = []
    selected_ids: set[str] = set()
    covered: set[str] = set()
    for municipality in municipality_names:
        if municipality in covered or len(selected) >= limit:
            continue
        choice = next(
            (
                row
                for row in rows
                if row["cell_id"] not in selected_ids and municipality in row.get("municipalities", [])
            ),
            None,
        )
        if choice is None:
            continue
        selected.append(choice)
        selected_ids.add(choice["cell_id"])
        covered.update(choice.get("municipalities", []))

    for row in rows:
        if len(selected) >= limit:
            break
        if row["cell_id"] in selected_ids:
            continue
        selected.append(row)
        selected_ids.add(row["cell_id"])
    return selected


def run(
    source_root: Path,
    state_path: Path,
    target_grid_path: Path,
    output_root: Path,
    report_path: Path,
    limit: int,
    existing_root: Path | None = None,
) -> dict[str, Any]:
    candidates = discover_candidates(source_root, state_path, target_grid_path, existing_root)
    selected = select_batch(candidates, limit)
    output_root.mkdir(parents=True, exist_ok=True)
    built: list[dict[str, Any]] = []
    failures: list[dict[str, str]] = []

    for row in selected:
        cell_id = row["cell_id"]
        try:
            candidate = runtime_bundle.build(source_root / cell_id, output_root / cell_id)
        except Exception as exc:
            failures.append({"cell_id": cell_id, "error": str(exc)})
            continue
        if candidate.get("safety", {}).get("runtime_mount_authorized") is not False:
            failures.append({"cell_id": cell_id, "error": "candidate unexpectedly authorized runtime mount"})
            continue
        if candidate.get("safety", {}).get("jouable_promotion_authorized") is not False:
            failures.append({"cell_id": cell_id, "error": "candidate unexpectedly authorized JOUABLE promotion"})
            continue
        built.append(
            {
                "cell_id": cell_id,
                "municipalities": row.get("municipalities", []),
                "candidate_digest": candidate.get("candidate_digest"),
                "stats": candidate.get("stats", {}),
            }
        )

    selected_municipalities = sorted({m for row in selected for m in row.get("municipalities", [])})
    built_municipalities = sorted({m for row in built for m in row.get("municipalities", [])})
    report = {
        "format": FORMAT,
        "limit": limit,
        "eligible_uncompiled_count": len(candidates),
        "selected_count": len(selected),
        "selected_cells": [row["cell_id"] for row in selected],
        "selected_municipalities": selected_municipalities,
        "selected_municipality_count": len(selected_municipalities),
        "built_count": len(built),
        "built_cells": built,
        "built_municipalities": built_municipalities,
        "built_municipality_count": len(built_municipalities),
        "failure_count": len(failures),
        "failures": failures,
        "runtime_mount_authorized": False,
        "jouable_promotion_authorized": False,
        "next_gate": "validate_runtime_candidate_then_attach_maturity_evidence_before_promotion",
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--target-grid", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--existing-root", type=Path)
    parser.add_argument("--limit", type=int, default=32)
    args = parser.parse_args()
    if args.limit < 1 or args.limit > 32:
        raise SystemExit("--limit must be between 1 and 32")
    report = run(
        args.source_root,
        args.state,
        args.target_grid,
        args.output_root,
        args.report,
        args.limit,
        args.existing_root,
    )
    print(
        "REGIONAL_RUNTIME_CANDIDATE_FRONTIER_OK",
        f"selected={report['selected_count']}",
        f"built={report['built_count']}",
        f"municipalities={report['built_municipality_count']}",
        f"failures={report['failure_count']}",
        "runtime_mount=false",
        "jouable_promotion=false",
    )
    return 1 if report["failure_count"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
