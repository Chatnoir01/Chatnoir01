#!/usr/bin/env python3
"""Rebind the Grand-Place municipality preflight to the refreshed road-cell v2 lock.

The historical municipality engine remains unchanged. This adapter validates the
new v2 candidate/source identities, delegates the official UrbIS WFS measurement,
then upgrades the emitted evidence with the road-semantic identity. It never
opens registration/runtime/JOUABLE rails.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve()
LEGACY_PATH = HERE.with_name("measure_road_cell_municipality_preflight.py")

EXPECTED_CANDIDATE_SEMANTIC_SHA256 = "8aaca3178894950a8a1efe8235e3313f34d4d23656b968a9cbf87666284acd7b"
EXPECTED_ROAD_SOURCE_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
EXPECTED_ROAD_SEMANTIC_SHA256 = "4ec4ba4ad46a999d3ea32ab4a42b6825d6e43f11fcae92ac9b7a4236222913e0"
TARGET_CELL_ID = "E148000_N170000"
TARGET_ANCHOR_ID = "grand_place"
CLOSED_RAILS = (
    "registration_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
)


def _load_legacy():
    spec = importlib.util.spec_from_file_location("municipality_preflight_legacy", LEGACY_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load historical municipality preflight")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _require_closed(node: dict[str, Any], context: str) -> None:
    for key in CLOSED_RAILS:
        if node.get(key) is not False:
            raise RuntimeError(f"{context}: authorization rail {key} must remain false")


def validate_candidate_v2(payload: dict[str, Any]) -> dict[str, Any]:
    if payload.get("schema") != "grand-bruxelles-road-cell-coverage-candidates-v2":
        raise RuntimeError("candidate lock schema drift")
    if payload.get("status") != "DISCOVERED_SOURCE_ONLY":
        raise RuntimeError("candidate lock must remain DISCOVERED_SOURCE_ONLY")
    if payload.get("semantic_sha256") != EXPECTED_CANDIDATE_SEMANTIC_SHA256:
        raise RuntimeError("candidate semantic SHA drift")
    if payload.get("road_source_sha256") != EXPECTED_ROAD_SOURCE_SHA256:
        raise RuntimeError("road source forensic SHA drift")
    if payload.get("road_semantic_sha256") != EXPECTED_ROAD_SEMANTIC_SHA256:
        raise RuntimeError("road semantic SHA drift")
    if int(payload.get("candidate_cell_count", -1)) != 8:
        raise RuntimeError("candidate cell count drift")
    _require_closed(payload, "candidate lock")
    matches = [c for c in payload.get("candidates", []) if c.get("grid_cell_id") == TARGET_CELL_ID]
    if len(matches) != 1:
        raise RuntimeError(f"expected exactly one {TARGET_CELL_ID} candidate")
    candidate = matches[0]
    _require_closed(candidate, TARGET_CELL_ID)
    if candidate.get("corridor_anchor_ids") != [TARGET_ANCHOR_ID]:
        raise RuntimeError("Grand-Place anchor identity drift")
    if [float(v) for v in candidate.get("bbox", [])] != [148000.0, 170000.0, 148500.0, 170500.0]:
        raise RuntimeError("Grand-Place candidate bbox drift")
    if int(candidate.get("road_count", -1)) != 2:
        raise RuntimeError("Grand-Place road count drift")
    if [int(v) for v in candidate.get("road_ids", [])] != [13842686, 684214770]:
        raise RuntimeError("Grand-Place road IDs drift")
    if int(candidate.get("point_hits", -1)) != 9 or int(candidate.get("segment_hits", -1)) != 7:
        raise RuntimeError("Grand-Place road hit accounting drift")
    return candidate


def _semantic_basis(result: dict[str, Any]) -> dict[str, Any]:
    basis = json.loads(json.dumps(result))
    basis["municipality_source"].pop("raw_payload_sha256", None)
    basis["municipality_coverage"].pop("transport_feature_ids", None)
    basis.pop("semantic_sha256", None)
    return basis


def run(candidate_path: Path, output_path: Path) -> dict[str, Any]:
    candidate_payload = json.loads(candidate_path.read_text(encoding="utf-8"))
    validate_candidate_v2(candidate_payload)

    legacy = _load_legacy()
    legacy.EXPECTED_CANDIDATE_SEMANTIC_SHA256 = EXPECTED_CANDIDATE_SEMANTIC_SHA256
    legacy.EXPECTED_ROAD_SOURCE_SHA256 = EXPECTED_ROAD_SOURCE_SHA256
    legacy.validate_candidate_lock = validate_candidate_v2
    temporary = output_path.with_suffix(".legacy.json")
    result = legacy.run(candidate_path, temporary)

    result["schema"] = "grand-bruxelles-road-cell-municipality-preflight-v3"
    result["candidate_source"]["semantic_sha256"] = EXPECTED_CANDIDATE_SEMANTIC_SHA256
    result["candidate_source"]["road_source_sha256"] = EXPECTED_ROAD_SOURCE_SHA256
    result["candidate_source"]["road_semantic_sha256"] = EXPECTED_ROAD_SEMANTIC_SHA256
    result["semantic_sha256"] = hashlib.sha256(
        json.dumps(_semantic_basis(result), ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    temporary.unlink(missing_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "ROAD_CELL_MUNICIPALITY_PREFLIGHT_V2_REBOUND: "
        f"cell={TARGET_CELL_ID} status={result['status']} sha256={result['semantic_sha256']}"
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    run(args.candidate, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
