#!/usr/bin/env python3
"""Persist one exact per-cell terrain runtime gate measurement fail-closed.

This tool never measures a gate and never promotes a cell. It only accepts an already
hashed measurement bundle whose cell identity and four prerequisite digests match the
current artifacts, then writes it to the canonical per-cell filename consumed by the
runtime gate evidence aggregator.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
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


evidence_mod = _load("terrain_gate_persistence_evidence", HERE / "build_terrain_runtime_gate_evidence.py")

PERSISTED_TARGETS = {
    "streaming": "terrain_streaming_gate_measurement.json",
    "performance": "terrain_performance_gate_measurement.json",
    "photo_match": "terrain_photo_match_gate_measurement.json",
}


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _single_persistable_gate(bundle: dict[str, Any]) -> str:
    gates = bundle.get("gates")
    if not isinstance(gates, dict) or len(gates) != 1:
        raise ValueError("persisted terrain runtime measurement must contain exactly one gate")
    gate = next(iter(gates))
    if gate not in PERSISTED_TARGETS:
        raise ValueError(f"runtime gate is not persistable through this contract: {gate}")
    return gate


def _atomic_write(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    try:
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        tmp.replace(path)
    finally:
        if tmp.exists():
            tmp.unlink()


def persist(
    terrain_path: Path,
    terrain_candidate_path: Path,
    secondary_path: Path,
    runtime_candidate_path: Path,
    measurement_path: Path,
    *,
    replace_fresh: bool = False,
) -> dict[str, Any]:
    terrain = _read(terrain_path)
    terrain_candidate = _read(terrain_candidate_path)
    secondary = _read(secondary_path)
    runtime_candidate = _read(runtime_candidate_path)
    cell_id, bindings = evidence_mod._expected_bindings(terrain, terrain_candidate, secondary, runtime_candidate)

    if terrain_path.parent.name != cell_id:
        raise ValueError("terrain LOD evidence must live in its canonical per-cell directory")

    bundle = _read(measurement_path)
    bundle_digest = evidence_mod._validate_bundle_digest(bundle, measurement_path)
    evidence_mod._validate_measurement_bundle(bundle, cell_id, bindings)
    gate = _single_persistable_gate(bundle)
    policy = bundle.get("policy")
    if not isinstance(policy, dict) or policy.get("runtime_promotion_allowed") is not False:
        raise ValueError("measurement bundle must explicitly keep runtime promotion disabled")

    target = terrain_path.parent / PERSISTED_TARGETS[gate]
    action = "created"
    if target.is_file():
        existing = _read(target)
        evidence_mod._validate_bundle_digest(existing, target)
        existing_gate = _single_persistable_gate(existing)
        if existing_gate != gate:
            raise ValueError(f"persisted filename gate mismatch: expected {gate}, found {existing_gate}")
        if existing == bundle:
            return {
                "cell_id": cell_id,
                "gate": gate,
                "target": str(target),
                "measurement_bundle_digest": bundle_digest,
                "action": "unchanged",
                "runtime_promotion_allowed": False,
            }

        stale_existing = False
        try:
            evidence_mod._validate_measurement_bundle(existing, cell_id, bindings)
        except ValueError as exc:
            if "stale against exact cell artifacts" in str(exc):
                stale_existing = True
            else:
                raise

        if stale_existing:
            action = "replaced_stale"
        elif replace_fresh:
            action = "replaced_fresh_explicitly"
        else:
            raise ValueError(
                "fresh persisted measurement already exists with different evidence; "
                "explicit --replace-fresh is required for a deliberate remeasurement"
            )

    _atomic_write(target, bundle)
    return {
        "cell_id": cell_id,
        "gate": gate,
        "target": str(target),
        "measurement_bundle_digest": bundle_digest,
        "action": action,
        "runtime_promotion_allowed": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terrain-lod", type=Path, required=True)
    parser.add_argument("--terrain-runtime-candidate", type=Path, required=True)
    parser.add_argument("--secondary-height-validation", type=Path, required=True)
    parser.add_argument("--runtime-candidate", type=Path, required=True)
    parser.add_argument("--measurement", type=Path, required=True)
    parser.add_argument("--replace-fresh", action="store_true")
    args = parser.parse_args()
    try:
        result = persist(
            args.terrain_lod,
            args.terrain_runtime_candidate,
            args.secondary_height_validation,
            args.runtime_candidate,
            args.measurement,
            replace_fresh=args.replace_fresh,
        )
    except Exception as exc:
        print(f"TERRAIN_GATE_MEASUREMENT_PERSIST_ERROR: {exc}")
        return 1
    print(
        "TERRAIN_GATE_MEASUREMENT_PERSIST_OK "
        f"cell={result['cell_id']} gate={result['gate']} action={result['action']} "
        f"digest={result['measurement_bundle_digest']} runtime_promotion=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
