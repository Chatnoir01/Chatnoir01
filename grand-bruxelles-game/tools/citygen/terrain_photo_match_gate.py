#!/usr/bin/env python3
"""Build fail-closed per-cell photo-match gate measurements.

The existing photo-match registry remains the source of truth for reference provenance,
camera approval, mismatch resolution and 0..5 scoring. This adapter adds the missing
CityGen requirement: an exact reference must be explicitly bound to one cell and the
four terrain/runtime digests before it can satisfy the `photo_match` runtime gate.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


streaming_mod = _load("terrain_photo_streaming", HERE / "terrain_streaming_gate.py")
gate_mod = _load("terrain_photo_gate_evidence", HERE / "build_terrain_runtime_gate_evidence.py")
photo_mod = _load("terrain_photo_registry", HERE.parent / "validate_photo_match.py")

MEASUREMENT_FORMAT = gate_mod.MEASUREMENT_FORMAT
CRS = streaming_mod.CRS
BINDING_FIELDS = (
    "terrain_lod_evidence_digest",
    "terrain_runtime_candidate_digest",
    "secondary_height_validation_digest",
    "runtime_candidate_digest",
)


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _validate_registry(path: Path) -> tuple[dict[str, Any], int, int]:
    try:
        total, complete = photo_mod.validate_manifest(path)
    except SystemExit as exc:
        raise ValueError(f"photo-match registry validation failed ({exc.code})") from None
    return _read(path), total, complete


def _binding_matches(binding: Any, cell_id: str, expected: dict[str, str]) -> bool:
    if not isinstance(binding, dict):
        return False
    if binding.get("cell_id") != cell_id or binding.get("crs") != CRS:
        return False
    return all(binding.get(key) == expected[key] for key in BINDING_FIELDS)


def _binding_targets_cell(binding: Any, cell_id: str) -> bool:
    return isinstance(binding, dict) and binding.get("cell_id") == cell_id


def build(streaming_probe_path: Path, manifest_path: Path, reference_id: str | None = None) -> dict[str, Any]:
    streaming_probe = _read(streaming_probe_path)
    cell_id = streaming_mod._validate_probe(streaming_probe)
    expected_bindings = copy.deepcopy(streaming_probe["bindings"])
    manifest, total, complete = _validate_registry(manifest_path)
    scale = manifest.get("score_scale")
    references = manifest.get("references")
    if not isinstance(scale, dict) or not isinstance(references, list):
        raise ValueError("photo-match registry contract missing")

    selected: list[dict[str, Any]] = []
    for raw in references:
        if not isinstance(raw, dict):
            continue
        if reference_id is not None and raw.get("id") != reference_id:
            continue
        binding = raw.get("citygen_binding")
        if _binding_targets_cell(binding, cell_id):
            if not _binding_matches(binding, cell_id, expected_bindings):
                raise ValueError(f"photo-match reference is stale against exact cell artifacts: {raw.get('id')}")
            selected.append(raw)

    if reference_id is not None and not any(isinstance(row, dict) and row.get("id") == reference_id for row in references):
        raise ValueError(f"unknown photo-match reference id: {reference_id}")
    if len(selected) > 1 and reference_id is None:
        raise ValueError("multiple exact photo-match references target cell; select one explicitly")

    passing_average = float(scale.get("passing_average", 0.0))
    critical_fields = list(scale.get("critical_fields") or [])
    metrics: dict[str, Any] = {
        "registry_reference_count": total,
        "registry_realism_complete_count": complete,
        "passing_average": passing_average,
        "critical_fields": critical_fields,
        "selected_reference_id": None,
        "selected_score_average": None,
        "selected_critical_scores": {},
    }

    if not selected:
        passed = False
        status = "blocked_no_exact_cell_photo_reference"
        source_reference = None
    else:
        reference = selected[0]
        source_reference = str(reference.get("id"))
        metrics["selected_reference_id"] = source_reference
        if reference.get("realism_complete") is not True:
            passed = False
            status = "blocked_exact_reference_not_realism_complete"
        else:
            scores = reference.get("scores")
            if not isinstance(scores, dict):
                raise ValueError("realism-complete exact photo reference has no score object")
            numeric = {field: float(scores[field]) for field in photo_mod.SCORE_FIELDS}
            average = sum(numeric.values()) / len(numeric)
            critical_scores = {field: numeric[field] for field in critical_fields}
            metrics["selected_score_average"] = average
            metrics["selected_critical_scores"] = critical_scores
            passed = average >= passing_average and all(value >= passing_average for value in critical_scores.values())
            if not passed:
                raise ValueError("generic photo-match validator accepted a complete reference below its scoring contract")
            status = "passed_exact_bound_realism_complete_photo_match"

    row = {
        "cell_id": cell_id,
        "gate": "photo_match",
        "passed": passed,
        "status": status,
        "source": "validated_photo_match_registry_with_exact_citygen_digest_binding",
        "reference_id": source_reference,
        "registry_digest": _digest(manifest),
        "metrics": metrics,
    }
    row["measurement_digest"] = _digest(row)
    bundle = {
        "format": MEASUREMENT_FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bindings": expected_bindings,
        "gates": {"photo_match": row},
        "policy": {
            "generic_photo_match_registry_reused": True,
            "exact_cell_digest_binding_required": True,
            "realism_complete_required": True,
            "global_photo_match_workflow_green_is_not_cell_proof": True,
            "reference_image_bytes_not_required_or_rebundled": True,
            "runtime_promotion_allowed": False,
        },
    }
    bundle["measurement_bundle_digest"] = _digest(bundle)
    return bundle


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--streaming-probe", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=Path("grand-bruxelles-game/data/qa/photo_match/manifest.json"))
    parser.add_argument("--reference-id")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        payload = build(args.streaming_probe, args.manifest, args.reference_id)
    except Exception as exc:
        print(f"TERRAIN_PHOTO_MATCH_GATE_ERROR: {exc}")
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    row = payload["gates"]["photo_match"]
    print(f"TERRAIN_PHOTO_MATCH_GATE_OK cell={payload['cell_id']} passed={str(row['passed']).lower()} status={row['status']} reference={row['reference_id']} runtime_promotion=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
