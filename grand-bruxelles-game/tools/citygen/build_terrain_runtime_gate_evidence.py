#!/usr/bin/env python3
"""Aggregate measured per-cell runtime gates without inventing missing evidence."""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


readiness_mod = _load_module("terrain_readiness", HERE / "build_terrain_runtime_readiness.py")
MEASUREMENT_FORMAT = "grand-bruxelles-terrain-runtime-gate-measurement-bundle-v1"
FORMAT = readiness_mod.GATE_EVIDENCE_FORMAT
CRS = readiness_mod.CRS
ALLOWED_GATES = tuple(readiness_mod.RUNTIME_GATES)
PERSISTED_MEASUREMENT_FILENAMES = (
    "terrain_streaming_gate_measurement.json",
    "terrain_performance_gate_measurement.json",
    "terrain_photo_match_gate_measurement.json",
)


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _require_digest(name: str, value: Any) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value.lower()):
        raise ValueError(f"{name} must be a sha256 hex digest")
    return value.lower()


def _expected_bindings(
    terrain: dict[str, Any], terrain_candidate: dict[str, Any], secondary: dict[str, Any], runtime_candidate: dict[str, Any]
) -> tuple[str, dict[str, str]]:
    cell_id, terrain_digest, terrain_candidate_digest, secondary_digest, runtime_digest = readiness_mod._validate_base(
        terrain, terrain_candidate, secondary, runtime_candidate
    )
    return cell_id, {
        "terrain_lod_evidence_digest": terrain_digest,
        "terrain_runtime_candidate_digest": terrain_candidate_digest,
        "secondary_height_validation_digest": secondary_digest,
        "runtime_candidate_digest": runtime_digest,
    }


def _validate_gate_rows(gates: Any, cell_id: str) -> dict[str, dict[str, Any]]:
    if not isinstance(gates, dict) or not gates:
        raise ValueError("terrain runtime gate evidence contains no measured gates")
    validated: dict[str, dict[str, Any]] = {}
    for gate, raw in gates.items():
        if gate not in ALLOWED_GATES:
            raise ValueError(f"unsupported runtime gate measurement: {gate}")
        if not isinstance(raw, dict):
            raise ValueError(f"runtime gate measurement must be an object: {gate}")
        if raw.get("gate") != gate or raw.get("cell_id") != cell_id:
            raise ValueError(f"runtime gate measurement identity mismatch: {gate}")
        if not isinstance(raw.get("passed"), bool) or not isinstance(raw.get("status"), str) or not raw.get("status"):
            raise ValueError(f"runtime gate measurement result missing: {gate}")
        measurement_digest = _require_digest(f"{gate} measurement digest", raw.get("measurement_digest"))
        view = copy.deepcopy(raw)
        view.pop("measurement_digest", None)
        if _digest(view) != measurement_digest:
            raise ValueError(f"runtime gate measurement digest mismatch: {gate}")
        validated[gate] = copy.deepcopy(raw)
    return validated


def _validate_measurement_bundle(bundle: dict[str, Any], cell_id: str, bindings: dict[str, str]) -> dict[str, dict[str, Any]]:
    if bundle.get("format") != MEASUREMENT_FORMAT or bundle.get("crs") != CRS:
        raise ValueError("unsupported terrain runtime gate measurement bundle")
    if bundle.get("cell_id") != cell_id:
        raise ValueError("terrain runtime gate measurement bundle identity mismatch")
    bundle_bindings = bundle.get("bindings")
    if not isinstance(bundle_bindings, dict):
        raise ValueError("terrain runtime gate measurement bindings missing")
    if bundle_bindings != bindings:
        raise ValueError("terrain runtime gate measurement bundle is stale against exact cell artifacts")
    return _validate_gate_rows(bundle.get("gates"), cell_id)


def _validate_bundle_digest(bundle: dict[str, Any], path: Path) -> str:
    bundle_digest = bundle.get("measurement_bundle_digest")
    if not isinstance(bundle_digest, str) or len(bundle_digest) != 64:
        raise ValueError(f"measurement bundle digest missing: {path}")
    view = copy.deepcopy(bundle)
    view.pop("measurement_bundle_digest", None)
    if _digest(view) != bundle_digest:
        raise ValueError(f"measurement bundle digest mismatch: {path}")
    return bundle_digest


def _validate_existing_evidence(
    evidence: dict[str, Any], cell_id: str, bindings: dict[str, str], path: Path
) -> tuple[dict[str, dict[str, Any]], list[str]]:
    if evidence.get("format") != FORMAT or evidence.get("crs") != CRS or evidence.get("cell_id") != cell_id:
        raise ValueError("existing terrain runtime gate evidence identity/format mismatch")
    if evidence.get("bindings") != bindings:
        raise ValueError("existing terrain runtime gate evidence is stale against exact cell artifacts")
    digest = _require_digest("existing terrain runtime gate evidence digest", evidence.get("gate_evidence_digest"))
    view = copy.deepcopy(evidence)
    view.pop("gate_evidence_digest", None)
    if _digest(view) != digest:
        raise ValueError(f"existing terrain runtime gate evidence digest mismatch: {path}")
    rows = _validate_gate_rows(evidence.get("gates"), cell_id)
    source_digests = evidence.get("measurement_bundle_digests")
    if not isinstance(source_digests, list):
        raise ValueError("existing terrain runtime gate evidence source bundle digests missing")
    return rows, [_require_digest("existing source measurement bundle digest", item) for item in source_digests]


def _merge_rows(target: dict[str, dict[str, Any]], rows: dict[str, dict[str, Any]]) -> None:
    for gate, row in rows.items():
        if gate in target and target[gate] != row:
            raise ValueError(f"conflicting measured runtime gate evidence: {gate}")
        target[gate] = row


def build(
    terrain_path: Path,
    terrain_candidate_path: Path,
    secondary_path: Path,
    runtime_candidate_path: Path,
    measurement_paths: list[Path],
    existing_evidence_path: Path | None = None,
    discover_persisted_measurements: bool = True,
) -> dict[str, Any]:
    terrain = _read(terrain_path)
    terrain_candidate = _read(terrain_candidate_path)
    secondary = _read(secondary_path)
    runtime_candidate = _read(runtime_candidate_path)
    cell_id, bindings = _expected_bindings(terrain, terrain_candidate, secondary, runtime_candidate)
    if not measurement_paths and existing_evidence_path is None and not discover_persisted_measurements:
        raise ValueError("at least one measured runtime gate source is required")

    gates: dict[str, dict[str, Any]] = {}
    source_bundle_digests: list[str] = []
    existing_reused = False
    if existing_evidence_path is not None:
        if not existing_evidence_path.is_file():
            raise ValueError(f"existing terrain runtime gate evidence missing: {existing_evidence_path}")
        existing_rows, existing_sources = _validate_existing_evidence(
            _read(existing_evidence_path), cell_id, bindings, existing_evidence_path
        )
        _merge_rows(gates, existing_rows)
        source_bundle_digests.extend(existing_sources)
        existing_reused = True

    explicit_paths = [path for path in measurement_paths]
    seen_paths = {str(path.resolve()) for path in explicit_paths if path.exists()}
    stale_persisted: list[str] = []
    persisted_checked: list[str] = []
    candidate_paths: list[tuple[Path, bool]] = [(path, False) for path in explicit_paths]
    if discover_persisted_measurements:
        for filename in PERSISTED_MEASUREMENT_FILENAMES:
            path = terrain_path.parent / filename
            if not path.is_file() or str(path.resolve()) in seen_paths:
                continue
            candidate_paths.append((path, True))
            persisted_checked.append(filename)

    for path, is_persisted in candidate_paths:
        bundle = _read(path)
        bundle_digest = _validate_bundle_digest(bundle, path)
        if is_persisted and bundle.get("bindings") != bindings:
            stale_persisted.append(path.name)
            continue
        rows = _validate_measurement_bundle(bundle, cell_id, bindings)
        source_bundle_digests.append(bundle_digest)
        _merge_rows(gates, rows)

    if not gates:
        raise ValueError("no fresh measured runtime gate evidence available")

    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bindings": bindings,
        "gates": dict(sorted(gates.items())),
        "measurement_bundle_digests": sorted(set(source_bundle_digests)),
        "measured_gate_count": len(gates),
        "missing_runtime_gates": [gate for gate in ALLOWED_GATES if gate not in gates],
        "policy": {
            "partial_measured_evidence_allowed": True,
            "missing_gates_are_never_inferred": True,
            "conflicting_measurements_fail_closed": True,
            "exact_per_cell_artifact_bindings_required": True,
            "existing_gate_evidence_reused": existing_reused,
            "persisted_measurement_files_checked": persisted_checked,
            "stale_persisted_measurements_skipped": stale_persisted,
            "runtime_promotion_allowed": False,
        },
    }
    result["gate_evidence_digest"] = _digest(result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terrain-lod", type=Path, required=True)
    parser.add_argument("--terrain-runtime-candidate", type=Path, required=True)
    parser.add_argument("--secondary-height-validation", type=Path, required=True)
    parser.add_argument("--runtime-candidate", type=Path, required=True)
    parser.add_argument("--measurement", type=Path, action="append", default=[])
    parser.add_argument("--existing-evidence", type=Path)
    parser.add_argument("--no-discover-persisted-measurements", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = build(
            args.terrain_lod,
            args.terrain_runtime_candidate,
            args.secondary_height_validation,
            args.runtime_candidate,
            list(args.measurement),
            existing_evidence_path=args.existing_evidence,
            discover_persisted_measurements=not args.no_discover_persisted_measurements,
        )
    except Exception as exc:
        print(f"TERRAIN_RUNTIME_GATE_EVIDENCE_ERROR: {exc}")
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    passed = sum(1 for row in result["gates"].values() if row.get("passed") is True)
    print(
        "TERRAIN_RUNTIME_GATE_EVIDENCE_OK "
        f"cell={result['cell_id']} measured={result['measured_gate_count']} passed={passed} "
        f"missing={len(result['missing_runtime_gates'])} stale_persisted={len(result['policy']['stale_persisted_measurements_skipped'])} "
        "runtime_promotion=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
