#!/usr/bin/env python3
"""Measure official municipality coverage for the locked Bourse road cell.

Evidence/preflight only. This adapter reuses the proven UrbIS Municipality WFS
engine while binding it to the current deterministic road-cell v2 catalog.
It cannot authorize registration, road mapping, runtime mount, rendering,
collision, safe spawn or JOUABLE promotion.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve()
LEGACY_PATH = HERE.with_name("measure_road_cell_municipality_preflight.py")

EXPECTED_CANDIDATE_SEMANTIC_SHA256 = "8aaca3178894950a8a1efe8235e3313f34d4d23656b968a9cbf87666284acd7b"
EXPECTED_ROAD_SOURCE_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
EXPECTED_ROAD_SEMANTIC_SHA256 = "4ec4ba4ad46a999d3ea32ab4a42b6825d6e43f11fcae92ac9b7a4236222913e0"
TARGET_CELL_ID = "E147500_N170000"
TARGET_ANCHOR_ID = "bourse"
TARGET_BBOX = [147500.0, 170000.0, 148000.0, 170500.0]
TARGET_ROAD_IDS = [8512036, 8512040, 12357557, 14391825, 15497309, 15497711, 15497818, 356328311, 411724192, 591894649, 860225856]
TARGET_ROAD_COUNT = 11
TARGET_POINT_HITS = 62
TARGET_SEGMENT_HITS = 53
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
    spec = importlib.util.spec_from_file_location("municipality_preflight_legacy_bourse", LEGACY_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load historical municipality preflight engine")
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

    candidates = payload.get("candidates")
    if not isinstance(candidates, list):
        raise RuntimeError("candidate list missing")
    matches = [c for c in candidates if isinstance(c, dict) and c.get("grid_cell_id") == TARGET_CELL_ID]
    if len(matches) != 1:
        raise RuntimeError(f"expected exactly one {TARGET_CELL_ID} candidate")
    candidate = matches[0]
    _require_closed(candidate, TARGET_CELL_ID)
    if candidate.get("corridor_anchor_ids") != [TARGET_ANCHOR_ID]:
        raise RuntimeError("Bourse anchor identity drift")
    if [float(v) for v in candidate.get("bbox", [])] != TARGET_BBOX:
        raise RuntimeError("Bourse candidate bbox drift")
    if int(candidate.get("road_count", -1)) != TARGET_ROAD_COUNT:
        raise RuntimeError("Bourse road count drift")
    if [int(v) for v in candidate.get("road_ids", [])] != TARGET_ROAD_IDS:
        raise RuntimeError("Bourse road IDs drift")
    if int(candidate.get("point_hits", -1)) != TARGET_POINT_HITS or int(candidate.get("segment_hits", -1)) != TARGET_SEGMENT_HITS:
        raise RuntimeError("Bourse road hit accounting drift")
    return candidate


def _semantic_basis(result: dict[str, Any]) -> dict[str, Any]:
    basis = json.loads(json.dumps(result))
    basis.pop("production_base_sha", None)
    basis["municipality_source"].pop("raw_payload_sha256", None)
    basis["municipality_coverage"].pop("transport_feature_ids", None)
    basis.pop("semantic_sha256", None)
    return basis


def run(candidate_path: Path, output_path: Path, production_base_sha: str) -> dict[str, Any]:
    if not re.fullmatch(r"[0-9a-f]{40}", production_base_sha):
        raise RuntimeError("production base SHA must be lowercase 40-hex")
    candidate_payload = json.loads(candidate_path.read_text(encoding="utf-8"))
    validate_candidate_v2(candidate_payload)

    legacy = _load_legacy()
    legacy.TARGET_CELL_ID = TARGET_CELL_ID
    legacy.TARGET_ANCHOR_ID = TARGET_ANCHOR_ID
    legacy.EXPECTED_CANDIDATE_SEMANTIC_SHA256 = EXPECTED_CANDIDATE_SEMANTIC_SHA256
    legacy.EXPECTED_ROAD_SOURCE_SHA256 = EXPECTED_ROAD_SOURCE_SHA256
    legacy.validate_candidate_lock = validate_candidate_v2
    temporary = output_path.with_suffix(".legacy.json")
    result = legacy.run(candidate_path, temporary)

    result["schema"] = "grand-bruxelles-road-cell-municipality-preflight-v3"
    result["production_base_sha"] = production_base_sha
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
        "BOURSE_ROAD_CELL_MUNICIPALITY_PREFLIGHT: "
        f"cell={TARGET_CELL_ID} status={result['status']} sha256={result['semantic_sha256']}"
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--production-base-sha", required=True)
    args = parser.parse_args()
    run(args.candidate, args.output, args.production_base_sha)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
