#!/usr/bin/env python3
"""Validate one sealed regional runtime candidate against the current durable source cell.

This is evidence generation only. It never changes runtime payloads, never authorizes a
mount, and never promotes a cell. A candidate whose authoritative source changed is
reported as blocked/stale so it can be rebuilt instead of silently reused.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-runtime-candidate-validation-v1"
CANDIDATE_FORMAT = "grand-bruxelles-runtime-candidate-bundle-v1"
CANDIDATE_BUILT_FORMAT = "grand-bruxelles-urbis-built-cell-candidate-v1"
RUNTIME_CELL_FORMAT = "grand-bruxelles-urbis-cell-runtime-v1"
RUNTIME_NETWORK_FORMAT = "grand-bruxelles-urbis-network-cell-runtime-v2"
REQUIRED_INPUTS = (
    "manifest.json",
    "raw/buildings.geojson",
    "raw/street_surfaces.geojson",
    "raw/street_axes.geojson",
    "raw/tram_network.geojson",
    "raw/train_network.geojson",
)
FORBIDDEN_AUTH = (
    "runtime_mount_authorized",
    "collision_authorized",
    "terrain_runtime_authorized",
    "jouable_promotion_authorized",
    "mobility_runtime_authorized",
)


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _digest(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ).hexdigest()


def _candidate_digest_matches(candidate: dict[str, Any]) -> bool:
    expected = candidate.get("candidate_digest")
    if not isinstance(expected, str) or not expected:
        return False
    payload = dict(candidate)
    payload.pop("candidate_digest", None)
    return _digest(payload) == expected


def _authorization_safe(payload: dict[str, Any]) -> bool:
    auth = payload.get("authorization")
    if not isinstance(auth, dict) or auth.get("candidate_only") is not True:
        return False
    return all(auth.get(key) is not True for key in FORBIDDEN_AUTH)


def validate(bundle_dir: Path, source_dir: Path) -> dict[str, Any]:
    candidate_path = bundle_dir / "candidate.json"
    manifest_path = bundle_dir / "manifest.json"
    runtime_cell_path = bundle_dir / "runtime" / "cell.game.json"
    runtime_network_path = bundle_dir / "runtime" / "network.game.json"
    required_bundle = (candidate_path, manifest_path, runtime_cell_path, runtime_network_path)
    if not all(path.is_file() for path in required_bundle):
        missing = [str(path.relative_to(bundle_dir)) for path in required_bundle if not path.is_file()]
        raise ValueError(f"candidate bundle files missing: {missing}")

    candidate = _read(candidate_path)
    manifest = _read(manifest_path)
    runtime_cell = _read(runtime_cell_path)
    runtime_network = _read(runtime_network_path)
    cell_id = str(candidate.get("cell_id", ""))
    checks: dict[str, bool] = {}
    blockers: list[str] = []

    def check(name: str, ok: bool, blocker: str | None = None) -> None:
        checks[name] = bool(ok)
        if not ok:
            blockers.append(blocker or name)

    check("candidate_format", candidate.get("format") == CANDIDATE_FORMAT)
    check("cell_identity_present", bool(cell_id))
    check("manifest_candidate_format", manifest.get("format") == CANDIDATE_BUILT_FORMAT)
    check("manifest_identity", manifest.get("cell_id") == cell_id)
    check("runtime_cell_format", runtime_cell.get("format") == RUNTIME_CELL_FORMAT)
    check("runtime_network_format", runtime_network.get("format") == RUNTIME_NETWORK_FORMAT)
    check("runtime_cell_identity", runtime_cell.get("cell_id") == cell_id)
    check("runtime_network_identity", runtime_network.get("cell_id") == cell_id)
    check("candidate_digest", _candidate_digest_matches(candidate), "candidate_digest_mismatch")

    promotion = manifest.get("promotion")
    check("promotion_contract_present", isinstance(promotion, dict))
    if isinstance(promotion, dict):
        check("production_discovery_disabled", promotion.get("production_discovery_eligible") is False)
        check("explicit_promotion_required", promotion.get("requires_explicit_validated_promotion") is True)
    else:
        check("production_discovery_disabled", False)
        check("explicit_promotion_required", False)

    safety = candidate.get("safety")
    expected_safety = {
        "official_plan_geometry_only": True,
        "building_height_invented": False,
        "collision_generated": False,
        "runtime_mount_authorized": False,
        "jouable_promotion_authorized": False,
    }
    check("candidate_safety_contract", isinstance(safety, dict))
    if isinstance(safety, dict):
        for key, expected in expected_safety.items():
            check(f"safety_{key}", safety.get(key) is expected)
    else:
        for key in expected_safety:
            check(f"safety_{key}", False)

    check("manifest_authorization", _authorization_safe(manifest))
    check("runtime_cell_authorization", _authorization_safe(runtime_cell))
    check("runtime_network_authorization", _authorization_safe(runtime_network))

    output_sha = candidate.get("output_sha256")
    check("output_hash_contract", isinstance(output_sha, dict))
    for rel, path in (
        ("manifest.json", manifest_path),
        ("runtime/cell.game.json", runtime_cell_path),
        ("runtime/network.game.json", runtime_network_path),
    ):
        expected = output_sha.get(rel) if isinstance(output_sha, dict) else None
        check(f"output_hash_{rel}", isinstance(expected, str) and expected == _sha(path), f"output_hash_mismatch:{rel}")

    input_sha = candidate.get("input_sha256")
    check("source_hash_contract", isinstance(input_sha, dict))
    source_hashes: dict[str, str | None] = {}
    for rel in REQUIRED_INPUTS:
        path = source_dir / rel
        actual = _sha(path) if path.is_file() else None
        source_hashes[rel] = actual
        expected = input_sha.get(rel) if isinstance(input_sha, dict) else None
        check(
            f"source_current_{rel}",
            isinstance(expected, str) and actual is not None and expected == actual,
            f"stale_or_missing_source:{rel}",
        )

    check("source_crs", candidate.get("source_crs") == "EPSG:31370")
    buildings = runtime_cell.get("buildings")
    check("runtime_buildings_list", isinstance(buildings, list))
    if isinstance(buildings, list):
        no_height = all(
            isinstance(item, dict)
            and "height" not in item
            and item.get("height_source") == "absent_pending_validated_height_contract"
            and item.get("visual_height_available") is False
            for item in buildings
        )
        check("unvalidated_heights_absent", no_height)

    validated = not blockers
    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "candidate_digest": candidate.get("candidate_digest"),
        "status": "validated" if validated else "blocked",
        "checks": checks,
        "blockers": blockers,
        "source_hashes_current": source_hashes,
        "maturity_evidence_ready": validated,
        "promotion_ready": False,
        "authorization": {
            "candidate_only": True,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "next_gate": (
            "attach_validated_runtime_candidate_evidence_to_cell_maturity_manifest"
            if validated
            else "rebuild_or_repair_candidate_before_maturity_attachment"
        ),
    }
    result["validation_digest"] = _digest(result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-dir", type=Path, required=True)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = validate(args.bundle_dir, args.source_dir)
    except Exception as exc:
        print(f"VALIDATE_RUNTIME_CANDIDATE_ERROR: {exc}")
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "VALIDATE_RUNTIME_CANDIDATE_" + ("OK" if result["status"] == "validated" else "BLOCKED"),
        f"cell={result['cell_id']}",
        f"blockers={len(result['blockers'])}",
        "runtime_mount_authorized=false jouable_promotion_authorized=false",
    )
    return 0 if result["status"] == "validated" else 1


if __name__ == "__main__":
    raise SystemExit(main())
