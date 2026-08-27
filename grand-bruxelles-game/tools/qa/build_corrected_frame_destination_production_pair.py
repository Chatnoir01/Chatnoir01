#!/usr/bin/env python3
import argparse
import copy
import hashlib
import json
from pathlib import Path

FALSE_KEYS = (
    "collision_authorized", "jouable_authorized", "jouable_promotion_authorized",
    "render_authorized", "rendered_geometry_authorized", "road_cell_mapping_authorized",
    "runtime_directory_scan_authorized", "runtime_mount_authorized", "safe_spawn_authorized",
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_json(path: Path):
    raw = path.read_bytes()
    return json.loads(raw), raw


def require_false_auth(obj, where):
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key in FALSE_KEYS and value is not False:
                raise AssertionError(f"{where}: authorization {key} must remain false")
            require_false_auth(value, f"{where}.{key}")
    elif isinstance(obj, list):
        for i, value in enumerate(obj):
            require_false_auth(value, f"{where}[{i}]")


def grid_from_cell(cell_id: str) -> str:
    parts = cell_id.split("-")
    if len(parts) != 4 or parts[0] != "bxl" or not parts[1].startswith("e") or not parts[2].startswith("n") or not parts[3].startswith("s"):
        raise AssertionError(f"invalid cell_id: {cell_id}")
    return f"E{parts[1][1:]}_N{parts[2][1:]}"


def build_pair(contract, crosswalk_candidate, readiness_candidate, current_crosswalk, current_readiness):
    source = contract["source"]
    expected = contract["expected"]
    policy = contract["policy"]
    if policy.get("write_production_files_authorized") is not False:
        raise AssertionError("pre-apply contract must not authorize direct production writes")
    if not policy.get("atomic_pair_required"):
        raise AssertionError("atomic_pair_required must be true")

    require_false_auth(crosswalk_candidate, "crosswalk_candidate")
    require_false_auth(readiness_candidate, "readiness_candidate")

    cw_rows = crosswalk_candidate.get("rows", [])
    rd_rows = readiness_candidate.get("destinations", [])
    if len(cw_rows) != expected["mapping_count"] or len(rd_rows) != expected["destination_count"]:
        raise AssertionError("candidate counts do not match contract")

    cw_by_id = {}
    for row in cw_rows:
        rid = int(row["road_osm_id"])
        if rid in cw_by_id:
            raise AssertionError(f"duplicate crosswalk road_osm_id {rid}")
        cw_by_id[rid] = row

    rd_by_id = {}
    for row in rd_rows:
        rid = int(row["road_osm_id"])
        if rid in rd_by_id:
            raise AssertionError(f"duplicate readiness road_osm_id {rid}")
        if row.get("destination_id") != f"road-{rid}":
            raise AssertionError(f"destination identity mismatch for {rid}")
        if row.get("readiness") != "REGISTERED_NOT_RENDERED":
            raise AssertionError(f"road {rid} must remain REGISTERED_NOT_RENDERED")
        rd_by_id[rid] = row

    if set(cw_by_id) != set(rd_by_id):
        raise AssertionError("crosswalk/readiness road identity sets differ")
    for rid, cw in cw_by_id.items():
        rd = rd_by_id[rid]
        if cw["cell_id"] != rd["cell_id"]:
            raise AssertionError(f"cell mismatch for road {rid}")

    hold_ids = {int(x) for x in expected["multicell_hold_ids"]}
    if hold_ids & set(cw_by_id):
        raise AssertionError("multicell HOLD leaked into unique crosswalk")
    if hold_ids & set(rd_by_id):
        raise AssertionError("multicell HOLD leaked into readiness")

    cells = {row["cell_id"] for row in cw_rows}
    if len(cells) != expected["mapped_cell_count"]:
        raise AssertionError("mapped cell count mismatch")
    for rep in expected["representatives"]:
        rid = int(rep["road_osm_id"])
        if rid not in cw_by_id or cw_by_id[rid]["cell_id"] != rep["cell_id"]:
            raise AssertionError(f"representative mismatch for {rid}")

    road_sha = source["road_source_sha256"]
    for row in rd_rows:
        if row.get("source_sha256") != road_sha or row.get("source_license") != source["license"]:
            raise AssertionError(f"source provenance mismatch for road {row['road_osm_id']}")

    out_cw = copy.deepcopy(current_crosswalk)
    out_cw["mapped_road_count"] = len(cw_rows)
    out_cw["mapped_cell_count"] = len(cells)
    out_cw["excluded_multicell_road_ids"] = sorted(hold_ids)
    out_cw["destination_readiness"] = "CORRECTED_FRAME_ROAD_CELL_CROSSWALK_EVIDENCE_ONLY"
    out_cw["mapping_policy"] = "unique_source_coverage_cell_only_corrected_epsg31370"
    out_cw["corrected_frame_source_sha256"] = road_sha
    out_cw["corrected_frame_candidate_semantic_sha256"] = source["crosswalk_semantic_sha256"]
    out_cw["rows"] = []
    for row in sorted(cw_rows, key=lambda r: int(r["road_osm_id"])):
        rid = int(row["road_osm_id"])
        out_cw["rows"].append({
            "cell_id": row["cell_id"],
            "grid_cell_id": grid_from_cell(row["cell_id"]),
            "road_osm_id": rid,
            "mapping_basis": "corrected_epsg31370_unique_source_coverage_cell_and_registered_bbox",
            "mapping_evidence_only": True,
            "road_cell_mapping_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        })

    out_rd = copy.deepcopy(current_readiness)
    out_rd["destination_count"] = len(rd_rows)
    out_rd["destinations"] = sorted(copy.deepcopy(rd_rows), key=lambda r: int(r["road_osm_id"]))
    out_rd["corrected_frame_source_sha256"] = road_sha
    out_rd["corrected_frame_candidate_semantic_sha256"] = source["readiness_semantic_sha256"]
    out_rd["migration_state"] = "CORRECTED_FRAME_REGISTERED_NOT_RENDERED"
    require_false_auth(out_cw, "generated_crosswalk")
    require_false_auth(out_rd, "generated_readiness")
    return out_cw, out_rd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--contract", type=Path, required=True)
    ap.add_argument("--crosswalk-candidate", type=Path, required=True)
    ap.add_argument("--readiness-candidate", type=Path, required=True)
    ap.add_argument("--current-crosswalk", type=Path, required=True)
    ap.add_argument("--current-readiness", type=Path, required=True)
    ap.add_argument("--out-crosswalk", type=Path, required=True)
    ap.add_argument("--out-readiness", type=Path, required=True)
    args = ap.parse_args()

    contract, _ = load_json(args.contract)
    cw, cw_raw = load_json(args.crosswalk_candidate)
    rd, rd_raw = load_json(args.readiness_candidate)
    current_cw, _ = load_json(args.current_crosswalk)
    current_rd, _ = load_json(args.current_readiness)

    if sha256_bytes(cw_raw) != contract["source"]["crosswalk_json_sha256"]:
        raise AssertionError("crosswalk candidate byte SHA mismatch")
    if sha256_bytes(rd_raw) != contract["source"]["readiness_json_sha256"]:
        raise AssertionError("readiness candidate byte SHA mismatch")
    if cw.get("semantic_sha256") != contract["source"]["crosswalk_semantic_sha256"]:
        raise AssertionError("crosswalk candidate semantic SHA mismatch")
    if rd.get("semantic_sha256") != contract["source"]["readiness_semantic_sha256"]:
        raise AssertionError("readiness candidate semantic SHA mismatch")

    out_cw, out_rd = build_pair(contract, cw, rd, current_cw, current_rd)
    args.out_crosswalk.parent.mkdir(parents=True, exist_ok=True)
    args.out_readiness.parent.mkdir(parents=True, exist_ok=True)
    args.out_crosswalk.write_text(json.dumps(out_cw, indent=2, sort_keys=True) + "\n")
    args.out_readiness.write_text(json.dumps(out_rd, indent=2, sort_keys=True) + "\n")
    print(f"CORRECTED_FRAME_PRODUCTION_PAIR_STAGED mapping={len(out_cw['rows'])} destinations={len(out_rd['destinations'])} cells={out_cw['mapped_cell_count']} write_authorized=false")


if __name__ == "__main__":
    main()
