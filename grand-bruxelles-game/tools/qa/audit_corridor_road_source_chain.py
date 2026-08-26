#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

PLAYABILITY_KEYS = (
    "collision_authorized",
    "jouable_authorized",
    "render_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
)
EXPECTED_ZONES = {"midi", "anneessens", "bourse", "grand_place"}
NON_DEGENERATE_EPSILON = 1.0e-6
WITNESS_SCHEMA = "grand-bruxelles-automatic-road-player-visual-gate-v1"
QA_ONLY_AUTHORIZATION = (
    "playability_claimed",
    "destination_advertisable",
    "jouable_authorized",
)


def fail(message: str) -> None:
    raise SystemExit(f"CORRIDOR_ROAD_SOURCE_CHAIN_FAIL: {message}")


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"cannot read {path}: {exc}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def _safe_repo_path(repo_root: Path, value: object, label: str) -> Path:
    if not isinstance(value, str) or not value.strip():
        fail(f"{label} path missing")
    rel = Path(value)
    if rel.is_absolute() or ".." in rel.parts:
        fail(f"{label} path escapes repository: {value!r}")
    root = repo_root.resolve()
    candidate = (repo_root / rel).resolve()
    if root != candidate and root not in candidate.parents:
        fail(f"{label} path escapes repository: {value!r}")
    return candidate


def _validate_accepted_player_witness(repo_root: Path, contract: dict, locked_source_sha: str, representative_by_zone: dict) -> dict:
    witness_contract = contract.get("accepted_player_witness")
    if not isinstance(witness_contract, dict):
        fail("accepted_player_witness contract missing")
    zone = witness_contract.get("zone")
    if zone not in EXPECTED_ZONES:
        fail(f"accepted player witness zone invalid: {zone!r}")
    representative = representative_by_zone.get(zone)
    if representative is None:
        fail(f"accepted player witness zone absent from representatives: {zone}")
    try:
        expected_road_id = int(witness_contract["osm_id"])
    except Exception:
        fail("accepted player witness osm_id invalid")
    if int(representative["osm_id"]) != expected_road_id:
        fail(f"accepted player witness representative mismatch zone={zone} contract={expected_road_id} representative={representative['osm_id']}")
    required_resolution = witness_contract.get("required_resolution")
    if required_resolution != [1280, 720]:
        fail(f"accepted player witness resolution contract must remain [1280, 720], got {required_resolution!r}")
    witness_path = _safe_repo_path(repo_root, witness_contract.get("path"), "accepted player witness")
    witness = load_json(witness_path)
    if witness.get("schema") != WITNESS_SCHEMA:
        fail(f"unexpected accepted player witness schema: {witness.get('schema')!r}")
    evidence = witness.get("evidence") or {}
    try:
        actual_road_id = int(evidence.get("witness_road_osm_id"))
    except Exception:
        fail("accepted player witness road id missing")
    if actual_road_id != expected_road_id:
        fail(f"accepted player witness road mismatch expected={expected_road_id} actual={actual_road_id}")
    if evidence.get("resolution") != required_resolution:
        fail(f"accepted player witness resolution mismatch expected={required_resolution!r} actual={evidence.get('resolution')!r}")
    source_contract = witness.get("source_contract") or {}
    if source_contract.get("lookup_mode") != "deterministic_runtime_index":
        fail("accepted player witness must use deterministic_runtime_index")
    expected_source_path = "res://" + str(contract["source_document"])
    if source_contract.get("source_path") != expected_source_path:
        fail(f"accepted player witness source path mismatch expected={expected_source_path!r} actual={source_contract.get('source_path')!r}")
    if source_contract.get("source_sha256") != locked_source_sha:
        fail("accepted player witness source sha mismatch")
    if source_contract.get("ground_collision_proven") is not True:
        fail("accepted player witness ground collision not proven")
    if source_contract.get("source_sightline_clear") is not True:
        fail("accepted player witness source sightline not proven")
    alignment = source_contract.get("road_axis_alignment")
    if not isinstance(alignment, (int, float)) or not math.isfinite(float(alignment)) or float(alignment) < 0.90:
        fail(f"accepted player witness road axis alignment insufficient: {alignment!r}")
    human_review = witness.get("human_review") or {}
    if human_review.get("status") != "keep":
        fail(f"accepted player witness human review must be keep, got {human_review.get('status')!r}")
    if human_review.get("full_frame_inspected") is not True:
        fail("accepted player witness full-frame review missing")
    if human_review.get("road_identity_matches_frame") is not True:
        fail("accepted player witness road identity not confirmed in frame")
    blockers = human_review.get("blocking_reasons")
    if blockers not in ([], None):
        fail(f"accepted player witness has blocking reasons: {blockers!r}")
    authorization = witness.get("authorization") or {}
    if authorization.get("qa_witness_accepted") is not True:
        fail("accepted player witness QA acceptance missing")
    if any(authorization.get(key) is not False for key in QA_ONLY_AUTHORIZATION):
        fail("accepted player witness must remain QA-only")
    return {"zone": zone, "osm_id": expected_road_id, "resolution": required_resolution, "source_sha256": locked_source_sha, "ground_collision_proven": True, "source_sightline_clear": True, "road_axis_alignment": float(alignment), "qa_witness_accepted": True, "playability_claimed": False, "destination_advertisable": False, "jouable_authorized": False}


def validate(repo_root: Path, contract_path: Path) -> dict:
    contract = load_json(contract_path)
    if contract.get("schema") != "grand-bruxelles-corridor-road-source-chain-contract-v3":
        fail("unexpected contract schema")
    locked_source_sha = contract.get("source_sha256")
    if not isinstance(locked_source_sha, str) or len(locked_source_sha) != 64:
        fail("contract must pin a 64-character source_sha256")
    index = load_json(repo_root / contract["runtime_index"])
    if index.get("format") != "grand-bruxelles-road-runtime-index-v1":
        fail("unexpected runtime index format")
    if index.get("source_lookup_only") is not True:
        fail("runtime index must stay source_lookup_only=true")
    authorization = index.get("authorization") or {}
    if authorization.get("source_lookup_only") is not True:
        fail("authorization must declare source_lookup_only=true")
    enabled = [key for key in PLAYABILITY_KEYS if authorization.get(key) is not False]
    if enabled:
        fail("source registry must not self-authorize playability: " + ",".join(enabled))
    documents = index.get("documents") or []
    document_paths = [document.get("path") for document in documents]
    duplicate_document_paths = {path for path in document_paths if path is not None and document_paths.count(path) > 1}
    if duplicate_document_paths:
        fail("duplicate runtime source document paths: " + ",".join(sorted(str(path) for path in duplicate_document_paths)))
    documents_by_path = {document.get("path"): document for document in documents}
    source_rel = contract["source_document"]
    if source_rel not in documents_by_path:
        fail(f"source document {source_rel} absent from runtime index")
    document = documents_by_path[source_rel]
    source_path = repo_root / source_rel
    actual_sha = sha256(source_path)
    if actual_sha != locked_source_sha:
        fail(f"locked source sha mismatch contract={locked_source_sha} actual={actual_sha}")
    if document.get("sha256") != actual_sha:
        fail(f"source sha mismatch index={document.get('sha256')} actual={actual_sha}")
    source = load_json(source_path)
    road_rows = [road for road in source.get("roads", []) if "osm_id" in road]
    roads = {}
    duplicate_source_ids = set()
    for road in road_rows:
        road_id = int(road["osm_id"])
        if road_id in roads:
            duplicate_source_ids.add(road_id)
        else:
            roads[road_id] = road
    if duplicate_source_ids:
        fail("duplicate OSM road ids in exact source: " + ",".join(str(value) for value in sorted(duplicate_source_ids)))
    indexed_ids = {int(value) for value in document.get("road_ids", [])}
    results = []
    seen = set()
    seen_zones = set()
    for representative in contract.get("representatives", []):
        zone = representative.get("zone")
        if zone in seen_zones:
            fail(f"duplicate representative zone {zone}")
        seen_zones.add(zone)
        road_id = int(representative["osm_id"])
        if road_id in seen:
            fail(f"duplicate representative {road_id}")
        seen.add(road_id)
        if road_id not in indexed_ids:
            fail(f"representative {road_id} absent from runtime index")
        road = roads.get(road_id)
        if road is None:
            fail(f"representative {road_id} absent from exact OSM source")
        for key in ("name", "class"):
            if road.get(key) != representative.get(key):
                fail(f"{road_id} {key} mismatch expected={representative.get(key)!r} actual={road.get(key)!r}")
        if road.get("drivable") is not True:
            fail(f"representative {road_id} is not source-drivable")
        points = road.get("points") or []
        if len(points) < 2:
            fail(f"representative {road_id} has fewer than 2 source points")
        for point in points:
            valid_point = isinstance(point, list) and len(point) == 2 and all(isinstance(value, (int, float)) and math.isfinite(value) for value in point)
            if not valid_point:
                fail(f"representative {road_id} has invalid source point {point!r}")
        polyline_length = sum(math.hypot(float(b[0]) - float(a[0]), float(b[1]) - float(a[1])) for a, b in zip(points, points[1:]))
        if not math.isfinite(polyline_length) or polyline_length <= NON_DEGENERATE_EPSILON:
            fail(f"representative {road_id} has degenerate source geometry polyline_length={polyline_length!r}")
        results.append({"zone": zone, "osm_id": road_id, "name": road["name"], "class": road["class"], "source_points": len(points), "source_polyline_length": round(polyline_length, 6), "playable_authorized": False})
    if seen_zones != EXPECTED_ZONES:
        missing = sorted(EXPECTED_ZONES - seen_zones)
        unexpected = sorted(seen_zones - EXPECTED_ZONES)
        fail(f"corridor zone coverage mismatch missing={missing} unexpected={unexpected}")
    if len(results) != 4:
        fail(f"expected 4 corridor representatives, got {len(results)}")
    representative_by_zone = {item["zone"]: item for item in results}
    accepted_player_witness = _validate_accepted_player_witness(repo_root, contract, locked_source_sha, representative_by_zone)
    output = {"schema": "grand-bruxelles-corridor-road-source-chain-result-v3", "production_base_sha": contract["production_base_sha"], "source_sha256": actual_sha, "source_sha_locked": True, "representatives": results, "accepted_player_witness": accepted_player_witness, "playability_claimed": False}
    print("CORRIDOR_ROAD_SOURCE_CHAIN_OK " + " ".join(f"{item['zone']}=road-{item['osm_id']}" for item in results) + f" witness={accepted_player_witness['zone']}:road-{accepted_player_witness['osm_id']} source_sha256={actual_sha}")
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = validate(args.repo_root, args.contract)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
