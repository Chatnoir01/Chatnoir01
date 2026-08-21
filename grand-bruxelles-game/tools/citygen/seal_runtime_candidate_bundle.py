#!/usr/bin/env python3
"""Seal a generated Brussels runtime bundle as QA-only candidate evidence.

The runtime compiler intentionally reuses the production payload schemas so Godot can
validate the candidate with the same parsers. This sealing step changes the *root*
manifest format to a candidate-only schema and refreshes hashes. Production discovery
only accepts ``grand-bruxelles-urbis-built-cell-v1``; therefore a sealed candidate is
fail-closed even if somebody accidentally copies it into the production cell root.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

PRODUCTION_BUILT_FORMAT = "grand-bruxelles-urbis-built-cell-v1"
CANDIDATE_BUILT_FORMAT = "grand-bruxelles-urbis-built-cell-candidate-v1"
RUNTIME_CELL_FORMAT = "grand-bruxelles-urbis-cell-runtime-v1"
RUNTIME_NETWORK_FORMAT = "grand-bruxelles-urbis-network-cell-runtime-v2"
CANDIDATE_FORMAT = "grand-bruxelles-runtime-candidate-bundle-v1"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _write(path: Path, value: dict[str, Any], *, compact: bool = False) -> None:
    text = (
        json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        if compact
        else json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)
    )
    path.write_text(text + "\n", encoding="utf-8")


def _sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _require_candidate_authorization(name: str, payload: dict[str, Any]) -> None:
    authorization = payload.get("authorization")
    if not isinstance(authorization, dict):
        raise ValueError(f"{name} authorization missing")
    if authorization.get("candidate_only") is not True:
        raise ValueError(f"{name} is not explicitly candidate-only")
    forbidden_true = (
        "runtime_mount_authorized",
        "collision_authorized",
        "terrain_runtime_authorized",
        "jouable_promotion_authorized",
        "mobility_runtime_authorized",
    )
    for key in forbidden_true:
        if authorization.get(key) is True:
            raise ValueError(f"{name} unexpectedly authorizes {key}")


def seal(bundle_dir: Path) -> dict[str, Any]:
    manifest_path = bundle_dir / "manifest.json"
    runtime_cell_path = bundle_dir / "runtime" / "cell.game.json"
    runtime_network_path = bundle_dir / "runtime" / "network.game.json"
    candidate_path = bundle_dir / "candidate.json"
    for path in (manifest_path, runtime_cell_path, runtime_network_path, candidate_path):
        if not path.is_file():
            raise ValueError(f"candidate bundle file missing: {path.relative_to(bundle_dir)}")

    manifest = _read(manifest_path)
    runtime_cell = _read(runtime_cell_path)
    runtime_network = _read(runtime_network_path)
    candidate = _read(candidate_path)

    cell_id = str(manifest.get("cell_id", ""))
    if not cell_id:
        raise ValueError("candidate cell identity missing")
    if manifest.get("format") != PRODUCTION_BUILT_FORMAT:
        raise ValueError("compiler root manifest format drift before sealing")
    if runtime_cell.get("format") != RUNTIME_CELL_FORMAT or runtime_network.get("format") != RUNTIME_NETWORK_FORMAT:
        raise ValueError("runtime payload schema drift")
    if runtime_cell.get("cell_id") != cell_id or runtime_network.get("cell_id") != cell_id:
        raise ValueError("runtime payload identity mismatch")
    if candidate.get("format") != CANDIDATE_FORMAT or candidate.get("cell_id") != cell_id:
        raise ValueError("candidate evidence identity/format mismatch")

    _require_candidate_authorization("manifest", manifest)
    _require_candidate_authorization("runtime cell", runtime_cell)
    _require_candidate_authorization("runtime network", runtime_network)

    safety = candidate.get("safety")
    if not isinstance(safety, dict):
        raise ValueError("candidate safety contract missing")
    expected_safety = {
        "official_plan_geometry_only": True,
        "building_height_invented": False,
        "collision_generated": False,
        "runtime_mount_authorized": False,
        "jouable_promotion_authorized": False,
    }
    for key, expected in expected_safety.items():
        if safety.get(key) is not expected:
            raise ValueError(f"candidate safety drift: {key}")

    buildings = runtime_cell.get("buildings")
    if not isinstance(buildings, list):
        raise ValueError("candidate buildings payload missing")
    for building in buildings:
        if not isinstance(building, dict):
            raise ValueError("candidate building record is not an object")
        if "height" in building:
            raise ValueError("candidate contains an unvalidated building height")
        if building.get("height_source") != "absent_pending_validated_height_contract":
            raise ValueError("candidate building height provenance drift")
        if building.get("visual_height_available") is not False:
            raise ValueError("candidate building unexpectedly exposes visual height")

    # The actual safety boundary: sealed QA bundles no longer have the production
    # root format accepted by BrusselsWorldStreamingRuntime discovery.
    manifest["format"] = CANDIDATE_BUILT_FORMAT
    manifest["promotion"] = {
        "state": "qa_candidate_only",
        "production_manifest_format": PRODUCTION_BUILT_FORMAT,
        "production_discovery_eligible": False,
        "requires_explicit_validated_promotion": True,
    }
    _write(manifest_path, manifest)

    candidate.pop("candidate_digest", None)
    candidate["sealed"] = {
        "root_manifest_format": CANDIDATE_BUILT_FORMAT,
        "production_manifest_format": PRODUCTION_BUILT_FORMAT,
        "production_discovery_eligible": False,
        "requires_explicit_validated_promotion": True,
    }
    candidate["output_sha256"] = {
        "manifest.json": _sha(manifest_path),
        "runtime/cell.game.json": _sha(runtime_cell_path),
        "runtime/network.game.json": _sha(runtime_network_path),
    }
    candidate["candidate_digest"] = _digest(candidate)
    _write(candidate_path, candidate)
    return candidate


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        candidate = seal(args.bundle_dir)
    except Exception as exc:
        print(f"SEAL_RUNTIME_CANDIDATE_ERROR: {exc}")
        return 1
    print(
        "SEAL_RUNTIME_CANDIDATE_OK "
        f"cell={candidate['cell_id']} root_format={candidate['sealed']['root_manifest_format']} "
        "production_discovery_eligible=false runtime_mount_authorized=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
