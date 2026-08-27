#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def load_json(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise RuntimeError(f"expected JSON object: {path}")
    return data


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def semantic_sha(payload: dict) -> str:
    basis = dict(payload)
    basis.pop("production_base_sha", None)
    basis.pop("semantic_sha256", None)
    raw = json.dumps(basis, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(raw)


def require_all_false(mapping: dict, label: str) -> None:
    if not isinstance(mapping, dict) or not mapping:
        raise RuntimeError(f"missing authorization map: {label}")
    opened = {key: value for key, value in mapping.items() if value is not False}
    if opened:
        raise RuntimeError(f"authorization drift in {label}: {opened}")


def require_contract(contract: dict, production_base_sha: str) -> None:
    if contract.get("schema") != "grand-bruxelles-corrected-frame-destination-atomic-migration-preflight-contract-v1":
        raise RuntimeError("atomic preflight contract schema drift")
    if contract.get("status") not in {"MEASUREMENT_PENDING", "LOCKED_ATOMIC_MIGRATION_PREFLIGHT_EVIDENCE_ONLY"}:
        raise RuntimeError("atomic preflight contract status drift")
    if contract.get("production_base_sha") != production_base_sha:
        raise RuntimeError("atomic preflight production base drift")
    source = contract.get("source") or {}
    if source.get("provider") != "OpenStreetMap contributors via Overpass API":
        raise RuntimeError("atomic preflight source provider drift")
    if source.get("license") != "ODbL-1.0" or source.get("crs") != "EPSG:31370":
        raise RuntimeError("atomic preflight source license/CRS drift")
    policy = contract.get("policy") or {}
    if policy.get("artifact_only") is not True or policy.get("crosswalk_and_readiness_must_be_one_to_one") is not True:
        raise RuntimeError("atomic preflight policy drift")
    if policy.get("multicell_routes_must_remain_hold") is not True or policy.get("atomic_migration_required") is not True:
        raise RuntimeError("atomic migration/HOLD policy drift")
    for key in (
        "production_frame_update_authorized",
        "replace_production_crosswalk_authorized",
        "replace_production_readiness_authorized",
        "road_cell_mapping_authorized",
        "runtime_probe_authorized",
    ):
        if policy.get(key) is not False:
            raise RuntimeError(f"atomic preflight policy opened: {key}")
    require_all_false(contract.get("authorization") or {}, "atomic preflight")


def road_cell_map(rows: list[dict], label: str) -> dict[int, str]:
    result: dict[int, str] = {}
    for row in rows:
        road_id = int(row["road_osm_id"])
        cell_id = str(row["cell_id"])
        if road_id in result:
            raise RuntimeError(f"duplicate road id in {label}: {road_id}")
        result[road_id] = cell_id
    return result


def measure(
    contract: dict,
    corrected_crosswalk: dict,
    corrected_readiness: dict,
    production_crosswalk: dict,
    production_readiness: dict,
    production_base_sha: str,
) -> dict:
    require_contract(contract, production_base_sha)
    source = contract["source"]
    expected = contract["expected"]

    if corrected_crosswalk.get("schema") != "grand-bruxelles-corrected-frame-road-cell-crosswalk-materialization-candidate-v1":
        raise RuntimeError("corrected crosswalk schema drift")
    if corrected_crosswalk.get("status") != "CANDIDATE_EVIDENCE_ONLY_NOT_APPLIED":
        raise RuntimeError("corrected crosswalk status drift")
    require_all_false(corrected_crosswalk.get("authorization") or {}, "corrected crosswalk")
    materialization_policy = corrected_crosswalk.get("materialization_policy") or {}
    if materialization_policy.get("replace_current_crosswalk_authorized") is not False:
        raise RuntimeError("corrected crosswalk replacement opened")
    if materialization_policy.get("write_production_crosswalk_authorized") is not False:
        raise RuntimeError("corrected crosswalk production write opened")

    if corrected_readiness.get("schema") != "grand-bruxelles-corrected-frame-road-destination-readiness-candidate-v1":
        raise RuntimeError("corrected readiness schema drift")
    if corrected_readiness.get("status") != "CANDIDATE_SOURCE_BACKED_REGISTERED_NOT_RENDERED":
        raise RuntimeError("corrected readiness status drift")
    require_all_false(corrected_readiness.get("authorization") or {}, "corrected readiness")

    if production_crosswalk.get("destination_readiness") != "ROAD_CELL_CROSSWALK_EVIDENCE_ONLY":
        raise RuntimeError("production crosswalk status drift")
    for key in (
        "road_cell_mapping_authorized",
        "runtime_directory_scan_authorized",
        "runtime_mount_authorized",
        "rendered_geometry_authorized",
        "collision_authorized",
        "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ):
        if production_crosswalk.get(key) is not False:
            raise RuntimeError(f"production crosswalk rail opened: {key}")
    require_all_false(production_readiness.get("authorization") or {}, "production readiness")

    corrected_map = road_cell_map(corrected_crosswalk.get("rows") or [], "corrected crosswalk")
    readiness_map = road_cell_map(corrected_readiness.get("destinations") or [], "corrected readiness")
    production_map = road_cell_map(production_crosswalk.get("rows") or [], "production crosswalk")
    production_readiness_map = road_cell_map(production_readiness.get("destinations") or [], "production readiness")

    hold_rows = corrected_crosswalk.get("multicell_hold_rows") or []
    hold_ids = [int(row["road_osm_id"]) for row in hold_rows]
    if len(hold_ids) != len(set(hold_ids)):
        raise RuntimeError("duplicate multicell HOLD road id")
    leaked = sorted(set(hold_ids) & set(corrected_map))
    if leaked:
        raise RuntimeError(f"multicell HOLD leaked into unique mappings: {leaked}")
    readiness_hold_ids = [int(row["road_osm_id"]) for row in (corrected_readiness.get("multicell_hold_rows") or [])]
    if sorted(readiness_hold_ids) != sorted(hold_ids):
        raise RuntimeError("crosswalk/readiness HOLD identity drift")
    readiness_hold_leaks = sorted(set(hold_ids) & set(readiness_map))
    if readiness_hold_leaks:
        raise RuntimeError(f"multicell HOLD leaked into readiness destinations: {readiness_hold_leaks}")

    if production_map != production_readiness_map:
        raise RuntimeError("production crosswalk/readiness are not one-to-one")
    if corrected_map != readiness_map:
        missing = sorted(set(corrected_map) - set(readiness_map))
        extra = sorted(set(readiness_map) - set(corrected_map))
        moved = sorted(rid for rid in set(corrected_map) & set(readiness_map) if corrected_map[rid] != readiness_map[rid])
        raise RuntimeError(f"corrected crosswalk/readiness mismatch missing={missing[:8]} extra={extra[:8]} moved={moved[:8]}")

    current_ids = set(production_map)
    candidate_ids = set(corrected_map)
    shared = current_ids & candidate_ids
    retained = sorted(rid for rid in shared if production_map[rid] == corrected_map[rid])
    changed = sorted(rid for rid in shared if production_map[rid] != corrected_map[rid])
    new = sorted(candidate_ids - current_ids)
    removed = sorted(current_ids - candidate_ids)

    accounting = {
        "production_mapping_count": len(production_map),
        "production_destination_count": len(production_readiness_map),
        "candidate_mapping_count": len(corrected_map),
        "candidate_destination_count": len(readiness_map),
        "candidate_mapped_cell_count": len(set(corrected_map.values())),
        "multicell_hold_count": len(hold_ids),
        "no_registered_overlap_count": int(corrected_readiness["accounting"]["no_registered_overlap_count"]),
        "retained_same_cell_count": len(retained),
        "changed_cell_count": len(changed),
        "new_destination_count": len(new),
        "removed_destination_count": len(removed),
    }
    expected_accounting = {key: int(expected[key]) for key in accounting}
    if accounting != expected_accounting:
        raise RuntimeError(f"atomic migration accounting drift: measured={accounting} expected={expected_accounting}")

    for row in corrected_readiness.get("destinations") or []:
        if row.get("readiness") != "REGISTERED_NOT_RENDERED":
            raise RuntimeError(f"candidate readiness opened for road {row.get('road_osm_id')}")
        for key in ("render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"):
            if row.get(key) is not False:
                raise RuntimeError(f"candidate destination rail opened: {row.get('road_osm_id')} {key}")

    for representative in expected.get("representatives") or []:
        road_id = int(representative["road_osm_id"])
        cell_id = str(representative["cell_id"])
        if corrected_map.get(road_id) != cell_id or readiness_map.get(road_id) != cell_id:
            raise RuntimeError(f"representative atomic binding drift: {road_id}")

    if corrected_crosswalk.get("semantic_sha256") != source["corrected_crosswalk_semantic_sha256"]:
        raise RuntimeError("corrected crosswalk semantic lock drift")
    if corrected_readiness.get("semantic_sha256") != source["corrected_readiness_semantic_sha256"]:
        raise RuntimeError("corrected readiness semantic lock drift")

    output = {
        "schema": "grand-bruxelles-corrected-frame-destination-atomic-migration-preflight-v1",
        "status": "ATOMIC_PAIR_PROVEN_EVIDENCE_ONLY_NOT_APPLIED",
        "production_base_sha": production_base_sha,
        "source": {
            "provider": source["provider"],
            "license": source["license"],
            "crs": source["crs"],
            "road_source_sha256": source["road_source_sha256"],
            "corrected_crosswalk_semantic_sha256": source["corrected_crosswalk_semantic_sha256"],
            "corrected_readiness_semantic_sha256": source["corrected_readiness_semantic_sha256"],
        },
        "accounting": accounting,
        "multicell_hold_road_ids": sorted(hold_ids),
        "retained_road_ids": retained,
        "changed_road_ids": changed,
        "new_road_ids": new,
        "removed_road_ids": removed,
        "representatives": contract["expected"]["representatives"],
        "policy": contract["policy"],
        "authorization": contract["authorization"],
    }
    output["semantic_sha256"] = semantic_sha(output)
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--corrected-crosswalk", required=True)
    parser.add_argument("--corrected-readiness", required=True)
    parser.add_argument("--production-crosswalk", required=True)
    parser.add_argument("--production-readiness", required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    contract = load_json(Path(args.contract))
    corrected_crosswalk_path = Path(args.corrected_crosswalk)
    corrected_readiness_path = Path(args.corrected_readiness)
    source = contract["source"]
    if sha256_bytes(corrected_crosswalk_path.read_bytes()) != source["corrected_crosswalk_json_sha256"]:
        raise RuntimeError("corrected crosswalk artifact bytes drift")
    if sha256_bytes(corrected_readiness_path.read_bytes()) != source["corrected_readiness_candidate_json_sha256"]:
        raise RuntimeError("corrected readiness artifact bytes drift")

    result = measure(
        contract,
        load_json(corrected_crosswalk_path),
        load_json(corrected_readiness_path),
        load_json(Path(args.production_crosswalk)),
        load_json(Path(args.production_readiness)),
        args.production_base_sha,
    )
    out = Path(args.output)
    out.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(
        "CORRECTED_FRAME_ATOMIC_MIGRATION_PREFLIGHT_OK",
        f"candidate={result['accounting']['candidate_mapping_count']}",
        f"holds={result['accounting']['multicell_hold_count']}",
        f"changed={result['accounting']['changed_cell_count']}",
        f"new={result['accounting']['new_destination_count']}",
        f"removed={result['accounting']['removed_destination_count']}",
        f"semantic={result['semantic_sha256']}",
    )


if __name__ == "__main__":
    main()
