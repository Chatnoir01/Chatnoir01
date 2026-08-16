#!/usr/bin/env python3
"""Validate and normalize compact secondary-height evidence for durable CityGen cache.

This helper is intentionally fail-closed. It never grants runtime approval; it only
copies already-produced second-source evidence after checking identity, CRS and the
zero-runtime-promotion contract.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

SECONDARY_OUT = "secondary_height_evidence.json"
VALIDATION_OUT = "secondary_height_validation.json"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _write(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def persist(secondary_path: Path, validation_path: Path, output_dir: Path) -> dict[str, Any]:
    secondary = _read(secondary_path)
    validation = _read(validation_path)

    cell = secondary.get("cell")
    if not isinstance(cell, str) or not cell.startswith("bxl-"):
        raise ValueError("secondary evidence has invalid cell identity")
    if validation.get("cell_id") != cell:
        raise ValueError("secondary/validation cell identity mismatch")
    if secondary.get("source_crs") != "EPSG:31370" or validation.get("crs") != "EPSG:31370":
        raise ValueError("secondary evidence must remain EPSG:31370")
    if secondary.get("runtime_approved") is not False:
        raise ValueError("secondary evidence must never carry runtime approval")
    policy = secondary.get("policy")
    if not isinstance(policy, dict) or policy.get("runtime_approval") is not False:
        raise ValueError("secondary evidence policy must forbid runtime approval")
    if validation.get("runtime_promotion_allowed") is not False:
        raise ValueError("runtime promotion must remain forbidden")
    if int(validation.get("runtime_approved_count", -1)) != 0:
        raise ValueError("runtime approved count must remain zero")

    candidate_count = int(validation.get("candidate_count", -1))
    validated = int(validation.get("validated_candidate_count", -1))
    blocked = int(validation.get("blocked_candidate_count", -1))
    counts = secondary.get("counts")
    if not isinstance(counts, dict):
        raise ValueError("secondary evidence counts missing")
    if candidate_count < 0 or validated < 0 or blocked < 0 or validated + blocked != candidate_count:
        raise ValueError("secondary validation candidate accounting is inconsistent")
    if int(counts.get("manual_frontier_candidates", -1)) != candidate_count:
        raise ValueError("secondary/manual candidate counts disagree")

    output_dir.mkdir(parents=True, exist_ok=True)
    _write(output_dir / SECONDARY_OUT, secondary)
    _write(output_dir / VALIDATION_OUT, validation)
    result = {
        "cell_id": cell,
        "candidate_count": candidate_count,
        "validated_candidate_count": validated,
        "blocked_candidate_count": blocked,
        "runtime_promotion_allowed": False,
        "next_action": validation.get("next_action"),
    }
    print("SECONDARY_HEIGHT_CACHE_OK", json.dumps(result, sort_keys=True))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--secondary", type=Path, required=True)
    parser.add_argument("--validation", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    persist(args.secondary, args.validation, args.output_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
