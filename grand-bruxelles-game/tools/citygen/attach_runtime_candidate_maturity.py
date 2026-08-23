#!/usr/bin/env python3
"""Attach validated QA-only runtime geometry evidence to one CityGen maturity manifest.

This step advances only the ``runtime_geometry`` maturity gate. It never authorizes a
runtime mount, collisions, terrain, or JOUABLE promotion, and it never upgrades the
cell maturity state. Evidence is accepted only when the sealed runtime candidate and
its validation still match the current durable authoritative source bytes.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any

MATURITY_FORMAT = "grand-bruxelles-cell-maturity-v1"
VALIDATION_FORMAT = "grand-bruxelles-runtime-candidate-validation-v1"
CANDIDATE_FORMAT = "grand-bruxelles-runtime-candidate-bundle-v1"
CANDIDATE_ROOT_FORMAT = "grand-bruxelles-urbis-built-cell-candidate-v1"
RUNTIME_UNCERTAINTY = "runtime geometry not generated or validated"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_false(name: str, value: Any) -> None:
    if value is not False:
        raise ValueError(f"{name} must remain false")


def attach(
    maturity_path: Path,
    validation_path: Path,
    candidate_path: Path,
    source_manifest_path: Path,
) -> dict[str, Any]:
    maturity = _read(maturity_path)
    validation = _read(validation_path)
    candidate = _read(candidate_path)
    source_manifest = _read(source_manifest_path)

    if maturity.get("format") != MATURITY_FORMAT:
        raise ValueError("unsupported maturity manifest format")
    if validation.get("format") != VALIDATION_FORMAT:
        raise ValueError("unsupported runtime validation format")
    if candidate.get("format") != CANDIDATE_FORMAT:
        raise ValueError("unsupported runtime candidate format")

    cell_id = str(maturity.get("cell_id") or "")
    if not cell_id:
        raise ValueError("maturity cell identity missing")
    for name, payload in (("validation", validation), ("candidate", candidate), ("source", source_manifest)):
        if payload.get("cell_id") != cell_id:
            raise ValueError(f"{name} cell identity mismatch")

    maturity_contract = maturity.get("maturity")
    if not isinstance(maturity_contract, dict):
        raise ValueError("maturity contract missing")
    gates = maturity_contract.get("gates")
    if not isinstance(gates, dict) or "runtime_geometry" not in gates:
        raise ValueError("runtime_geometry maturity gate missing")
    if maturity_contract.get("state") != "data_ready":
        raise ValueError("runtime geometry evidence may only attach to data_ready cells")

    if validation.get("status") != "validated":
        raise ValueError("runtime candidate validation is not validated")
    blockers = validation.get("blockers")
    if blockers not in ([], None):
        raise ValueError("runtime candidate validation still has blockers")
    if validation.get("maturity_evidence_ready") is not True:
        raise ValueError("runtime validation does not authorize maturity evidence")
    _require_false("validation promotion_ready", validation.get("promotion_ready"))
    validation_auth = validation.get("authorization")
    if not isinstance(validation_auth, dict) or validation_auth.get("candidate_only") is not True:
        raise ValueError("validation candidate-only authorization missing")
    _require_false("validation runtime_mount_authorized", validation_auth.get("runtime_mount_authorized"))
    _require_false("validation jouable_promotion_authorized", validation_auth.get("jouable_promotion_authorized"))

    sealed = candidate.get("sealed")
    if not isinstance(sealed, dict):
        raise ValueError("candidate seal contract missing")
    if sealed.get("root_manifest_format") != CANDIDATE_ROOT_FORMAT:
        raise ValueError("candidate root is not sealed QA-only format")
    _require_false("candidate production_discovery_eligible", sealed.get("production_discovery_eligible"))
    if sealed.get("requires_explicit_validated_promotion") is not True:
        raise ValueError("candidate explicit promotion contract missing")

    safety = candidate.get("safety")
    if not isinstance(safety, dict):
        raise ValueError("candidate safety contract missing")
    if safety.get("official_plan_geometry_only") is not True:
        raise ValueError("candidate is not official plan geometry")
    _require_false("candidate runtime_mount_authorized", safety.get("runtime_mount_authorized"))
    _require_false("candidate jouable_promotion_authorized", safety.get("jouable_promotion_authorized"))
    _require_false("candidate collision_generated", safety.get("collision_generated"))
    _require_false("candidate building_height_invented", safety.get("building_height_invented"))

    candidate_digest = candidate.get("candidate_digest")
    if not isinstance(candidate_digest, str) or not candidate_digest:
        raise ValueError("candidate digest missing")
    candidate_without_digest = copy.deepcopy(candidate)
    candidate_without_digest.pop("candidate_digest", None)
    if _digest(candidate_without_digest) != candidate_digest:
        raise ValueError("candidate digest mismatch")
    if validation.get("candidate_digest") != candidate_digest:
        raise ValueError("validation candidate digest mismatch")

    source_hashes = validation.get("source_hashes_current")
    input_hashes = candidate.get("input_sha256")
    if not isinstance(source_hashes, dict) or not isinstance(input_hashes, dict):
        raise ValueError("source hash contract missing")
    if source_hashes != input_hashes:
        raise ValueError("candidate input hashes differ from validated source hashes")
    source_root = source_manifest_path.parent
    for relative, expected in sorted(source_hashes.items()):
        if not isinstance(relative, str) or not isinstance(expected, str):
            raise ValueError("invalid source hash record")
        path = source_root / relative
        if not path.is_file():
            raise ValueError(f"current durable source payload missing: {relative}")
        if _sha(path) != expected:
            raise ValueError(f"current durable source drift: {relative}")

    validation_digest = validation.get("validation_digest")
    if not isinstance(validation_digest, str) or not validation_digest:
        raise ValueError("validation digest missing")

    evidence: dict[str, Any] = {
        "status": "validated",
        "gate_ready": True,
        "contract": "sealed QA-only runtime candidate validated against current durable authoritative source hashes",
        "cell_id": cell_id,
        "candidate_format": CANDIDATE_FORMAT,
        "candidate_root_format": CANDIDATE_ROOT_FORMAT,
        "candidate_digest": candidate_digest,
        "validation_format": VALIDATION_FORMAT,
        "validation_digest": validation_digest,
        "source_manifest_sha256": source_hashes.get("manifest.json"),
        "source_hashes_current": dict(sorted(source_hashes.items())),
        "output_sha256": candidate.get("output_sha256", {}),
        "stats": candidate.get("stats", {}),
        "production_discovery_eligible": False,
        "requires_explicit_validated_promotion": True,
        "runtime_mount_authorized": False,
        "jouable_promotion_authorized": False,
        "collision_authorized": False,
        "terrain_runtime_authorized": False,
    }
    evidence["evidence_digest"] = _digest(evidence)

    result = copy.deepcopy(maturity)
    result.pop("maturity_digest", None)
    result["maturity"]["gates"]["runtime_geometry"] = True
    result["runtime_geometry_evidence"] = evidence
    uncertainties = result.get("uncertainties")
    if isinstance(uncertainties, list):
        result["uncertainties"] = [item for item in uncertainties if item != RUNTIME_UNCERTAINTY]
    result["maturity_digest"] = _digest(result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--maturity", type=Path, required=True)
    parser.add_argument("--validation", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--source-manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = attach(args.maturity, args.validation, args.candidate, args.source_manifest)
    except Exception as exc:
        print(f"RUNTIME_MATURITY_ATTACHMENT_ERROR: {exc}")
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "RUNTIME_MATURITY_ATTACHMENT_OK",
        f"cell={result['cell_id']}",
        "runtime_geometry=true",
        f"state={result['maturity']['state']}",
        "runtime_mount=false",
        "jouable_promotion=false",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
