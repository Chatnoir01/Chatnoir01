#!/usr/bin/env python3
"""Select CityGen cells needing independent regional secondary-height evidence.

A cell is fresh only when both persisted evidence files are internally safe and the
validation is bound to the exact current autonomous height-candidate digest and the
exact persisted secondary-evidence digest. Previous failures are rotated to the end
of the queue so one bad source cell cannot starve the regional rollout.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

HEIGHT_FORMAT = "grand-bruxelles-cell-building-height-candidates-v1"
SECONDARY_SCHEMA = "grand-bruxelles-ixelles-semantic-dsm-comparison-v1"
VALIDATION_FORMAT = "grand-bruxelles-citygen-secondary-height-validation-v1"
TERRAIN_FORMAT = "grand-bruxelles-cell-dtm-lod-evidence-v1"
CRS = "EPSG:31370"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _hex_digest(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(ch in "0123456789abcdef" for ch in value.casefold())


def _embedded_digest_valid(payload: dict[str, Any], field: str) -> bool:
    expected = payload.get(field)
    if not _hex_digest(expected):
        return False
    unsigned = {key: value for key, value in payload.items() if key != field}
    return _digest(unsigned) == str(expected).casefold()


def _valid_height_source(cell_id: str, payload: dict[str, Any]) -> tuple[bool, str | None, int]:
    if payload.get("format") != HEIGHT_FORMAT or payload.get("crs") != CRS or payload.get("cell_id") != cell_id:
        return False, None, 0
    if payload.get("runtime_promotion_allowed") is not False or payload.get("runtime_approved_count") != 0:
        return False, None, 0
    if not _embedded_digest_valid(payload, "candidate_digest"):
        return False, None, 0
    digest = str(payload["candidate_digest"]).casefold()
    rows = payload.get("buildings")
    count = payload.get("candidate_count")
    if not isinstance(rows, list) or not isinstance(count, int) or isinstance(count, bool) or count < 1:
        return False, None, 0
    if any(not isinstance(row, dict) or row.get("runtime_approved") is not False for row in rows):
        return False, None, 0
    measured = [row for row in rows if row.get("candidate_height_m") is not None]
    if len(measured) != count:
        return False, None, 0
    return True, digest, count


def _valid_terrain(cell_id: str, payload: dict[str, Any]) -> bool:
    if payload.get("format") != TERRAIN_FORMAT or payload.get("crs") != CRS or payload.get("cell_id") != cell_id:
        return False
    if payload.get("runtime_approved") is not False:
        return False
    if not _embedded_digest_valid(payload, "evidence_digest"):
        return False
    selection = payload.get("selection") or {}
    return isinstance(selection, dict) and selection.get("runtime_approved") is False and selection.get("selected_resolution_m") is not None


def _fresh_pair(cell_id: str, cell: Path, source_digest: str, candidate_count: int) -> bool:
    secondary_path = cell / "secondary_height_evidence.json"
    validation_path = cell / "secondary_height_validation.json"
    if not secondary_path.is_file() or not validation_path.is_file():
        return False
    try:
        secondary = _read(secondary_path)
        validation = _read(validation_path)
    except Exception:
        return False

    if secondary.get("schema") != SECONDARY_SCHEMA or secondary.get("cell") != cell_id or secondary.get("source_crs") != CRS:
        return False
    if secondary.get("runtime_approved") is not False or (secondary.get("policy") or {}).get("runtime_approval") is not False:
        return False
    counts = secondary.get("counts") or {}
    if not isinstance(counts, dict) or counts.get("height_candidate_source_count") != candidate_count:
        return False

    if validation.get("format") != VALIDATION_FORMAT or validation.get("cell_id") != cell_id or validation.get("crs") != CRS:
        return False
    if validation.get("height_candidate_source_kind") != "autonomous_measured_height_candidates":
        return False
    if validation.get("source_candidate_digest") != source_digest:
        return False
    if validation.get("secondary_evidence_digest") != _digest(secondary):
        return False
    if not _embedded_digest_valid(validation, "validation_digest"):
        return False
    if validation.get("runtime_promotion_allowed") is not False or validation.get("runtime_approved_count") != 0:
        return False
    declared = validation.get("candidate_count")
    validated = validation.get("validated_candidate_count")
    blocked = validation.get("blocked_candidate_count")
    if declared != candidate_count or not isinstance(validated, int) or not isinstance(blocked, int):
        return False
    if validated < 0 or blocked < 0 or validated + blocked != candidate_count:
        return False
    rows = validation.get("candidates")
    if not isinstance(rows, list) or len(rows) != candidate_count or any(
        not isinstance(row, dict) or row.get("runtime_approved") is not False for row in rows
    ):
        return False
    return True


def _previous_failures(path: Path | None) -> set[str]:
    if path is None or not path.is_file():
        return set()
    try:
        payload = _read(path)
    except Exception:
        return set()
    values = payload.get("failed_cells") or []
    return {str(value) for value in values if isinstance(value, str) and value.startswith("bxl-")}


def select(source_root: Path, limit: int, previous_report: Path | None = None) -> dict[str, Any]:
    if limit < 1 or limit > 16:
        raise ValueError("batch_size must be between 1 and 16")
    previous_failed = _previous_failures(previous_report)
    fresh: list[str] = []
    eligible: list[str] = []
    rejected: list[dict[str, str]] = []

    for cell in sorted((p for p in source_root.iterdir() if p.is_dir()), key=lambda p: p.name) if source_root.exists() else []:
        buildings = cell / "raw" / "buildings.geojson"
        heights_path = cell / "building_height_candidates.json"
        terrain_path = cell / "terrain_lod_evidence.json"
        if not buildings.is_file() or buildings.stat().st_size == 0 or not heights_path.is_file() or not terrain_path.is_file():
            continue
        try:
            heights = _read(heights_path)
            terrain = _read(terrain_path)
        except Exception as exc:
            rejected.append({"cell_id": cell.name, "reason": f"invalid prerequisite JSON: {exc}"})
            continue
        valid_height, source_digest, candidate_count = _valid_height_source(cell.name, heights)
        if not valid_height or source_digest is None:
            rejected.append({"cell_id": cell.name, "reason": "unsafe, tampered or unsupported autonomous height candidate contract"})
            continue
        if not _valid_terrain(cell.name, terrain):
            rejected.append({"cell_id": cell.name, "reason": "unsafe, tampered or unsupported terrain LOD contract"})
            continue
        if _fresh_pair(cell.name, cell, source_digest, candidate_count):
            fresh.append(cell.name)
        else:
            eligible.append(cell.name)

    eligible.sort(key=lambda cell_id: (cell_id in previous_failed, cell_id))
    selected = eligible[:limit]
    return {
        "format": "grand-bruxelles-citygen-secondary-height-selection-v1",
        "eligible_count": len(eligible),
        "fresh_count": len(fresh),
        "rejected_count": len(rejected),
        "selected_cells": selected,
        "previous_failed_deprioritized": [cell_id for cell_id in selected if cell_id in previous_failed],
        "rejected": rejected,
        "policy": {
            "autonomous_height_candidates_only": True,
            "terrain_lod_required": True,
            "embedded_source_digest_validation": True,
            "exact_source_digest_freshness": True,
            "exact_secondary_digest_freshness": True,
            "previous_failure_rotation": True,
            "runtime_promotion_allowed": False,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--previous-report", type=Path)
    parser.add_argument("--worklist", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    result = select(args.source_root, args.batch_size, args.previous_report)
    args.worklist.parent.mkdir(parents=True, exist_ok=True)
    args.worklist.write_text("".join(cell_id + "\n" for cell_id in result["selected_cells"]), encoding="utf-8")
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "SECONDARY_HEIGHT_SELECTION_OK",
        f"eligible={result['eligible_count']}",
        f"fresh={result['fresh_count']}",
        f"rejected={result['rejected_count']}",
        f"selected={len(result['selected_cells'])}",
        "runtime_promotion=false",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
