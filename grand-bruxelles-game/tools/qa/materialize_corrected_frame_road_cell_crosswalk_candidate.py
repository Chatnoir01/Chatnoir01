#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _sha256(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _canonical_sha(obj):
    return hashlib.sha256(
        json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ).hexdigest()


def _all_false(mapping):
    return isinstance(mapping, dict) and mapping and all(v is False for v in mapping.values())


def materialize(contract_path: Path, plan_path: Path, repo_root: Path, production_base_sha: str):
    contract = _load(contract_path)
    assert contract["schema"] == "grand-bruxelles-corrected-frame-road-cell-crosswalk-materialization-contract-v1"
    assert contract["status"] in {"MEASUREMENT_PENDING", "LOCKED_CANDIDATE_EVIDENCE_ONLY"}
    assert contract["production_base_sha"] == production_base_sha
    assert _all_false(contract["authorization"])
    policy = contract["materialization_policy"]
    assert policy["artifact_only"] is True
    assert policy["replace_current_crosswalk_authorized"] is False
    assert policy["write_production_crosswalk_authorized"] is False
    assert policy["multicell_mapping_authorized"] is False
    assert policy["unique_mapping_only"] is True
    assert policy["atomic_followup_required"] is True

    source = contract["source"]
    road_source = repo_root / source["road_source_path"]
    assert _sha256(road_source) == source["road_source_sha256"]

    plan_contract = _load(repo_root / source["migration_plan_contract_path"])
    assert plan_contract["status"] == "LOCKED_MIGRATION_PLAN_EVIDENCE_ONLY"
    assert plan_contract["locked_evidence"]["semantic_sha256"] == source["migration_plan_semantic_sha256"]
    assert plan_contract["locked_evidence"]["accounting"] == contract["expected"]
    assert all(v is False for v in plan_contract["authorization"].values())

    candidate_contract = _load(repo_root / source["candidate_contract_path"])
    assert candidate_contract["semantic_sha256"] == source["candidate_semantic_sha256"]
    assert candidate_contract["promotion_policy"]["replace_current_crosswalk_authorized"] is False
    assert all(v is False for v in candidate_contract["authorization"].values())

    current = _load(repo_root / source["current_crosswalk_path"])
    assert current["road_cell_mapping_authorized"] is False
    assert current["rendered_geometry_authorized"] is False
    assert current["collision_authorized"] is False
    assert current["jouable_promotion_authorized"] is False
    current_ids = {int(row["road_osm_id"]) for row in current["rows"]}
    assert len(current_ids) == len(current["rows"])

    plan = _load(plan_path)
    assert plan["schema"] == "grand-bruxelles-corrected-frame-road-cell-migration-plan-v1"
    assert plan["status"] == "MIGRATION_PLAN_EVIDENCE_ONLY"
    assert plan["semantic_sha256"] == source["migration_plan_semantic_sha256"]
    assert plan["accounting"] == contract["expected"]
    assert all(v is False for v in plan["authorization"].values())

    rows = []
    for row in plan["retained_rows"] + plan["changed_rows"]:
        rows.append({"road_osm_id": int(row["road_osm_id"]), "cell_id": row["candidate_cell_id"]})
    for row in plan["newly_mappable_rows"]:
        rows.append({"road_osm_id": int(row["road_osm_id"]), "cell_id": row["candidate_cell_id"]})
    rows.sort(key=lambda row: (row["road_osm_id"], row["cell_id"]))
    row_ids = [row["road_osm_id"] for row in rows]
    assert len(row_ids) == len(set(row_ids)) == contract["expected"]["candidate_unique_mapped_road_count"]

    hold_rows = sorted(
        ({"road_osm_id": int(row["road_osm_id"]), "hit_cells": sorted(row["hit_cells"])} for row in plan["multicell_hold_rows"]),
        key=lambda row: row["road_osm_id"],
    )
    hold_ids = {row["road_osm_id"] for row in hold_rows}
    assert len(hold_rows) == contract["expected"]["candidate_multicell_road_count"]
    assert not (set(row_ids) & hold_ids)

    removed_ids = {int(row["road_osm_id"]) for row in plan["no_longer_mappable_rows"]}
    changed_ids = {int(row["road_osm_id"]) for row in plan["changed_rows"]}
    retained_ids = {int(row["road_osm_id"]) for row in plan["retained_rows"]}
    assert current_ids == removed_ids | changed_ids | retained_ids
    assert len(removed_ids) == contract["expected"]["no_longer_mappable_count"]

    cell_counts = {}
    for row in rows:
        cell_counts[row["cell_id"]] = cell_counts.get(row["cell_id"], 0) + 1

    output = {
        "schema": "grand-bruxelles-corrected-frame-road-cell-crosswalk-materialization-candidate-v1",
        "status": "CANDIDATE_EVIDENCE_ONLY_NOT_APPLIED",
        "production_base_sha": production_base_sha,
        "source": {
            "provider": source["provider"],
            "license": source["license"],
            "road_source_sha256": source["road_source_sha256"],
            "migration_plan_semantic_sha256": source["migration_plan_semantic_sha256"],
            "candidate_semantic_sha256": source["candidate_semantic_sha256"],
            "crs": source["crs"],
            "origin_easting_m": source["origin_easting_m"],
            "origin_northing_m": source["origin_northing_m"],
            "formula": source["formula"],
        },
        "accounting": {
            **contract["expected"],
            "candidate_cell_counts": dict(sorted(cell_counts.items())),
        },
        "rows": rows,
        "multicell_hold_rows": hold_rows,
        "materialization_policy": policy,
        "authorization": contract["authorization"],
    }
    basis = dict(output)
    basis.pop("production_base_sha")
    output["semantic_sha256"] = _canonical_sha(basis)

    if contract["status"] == "LOCKED_CANDIDATE_EVIDENCE_ONLY":
        locked = contract["locked_evidence"]
        assert locked["semantic_sha256"] == output["semantic_sha256"]
        assert locked["candidate_unique_mapped_road_count"] == len(rows)
        assert locked["candidate_multicell_road_count"] == len(hold_rows)
        assert isinstance(locked["artifact_id"], int) and locked["artifact_id"] > 0
        for key in ("artifact_sha256", "candidate_json_sha256", "semantic_sha256"):
            assert isinstance(locked[key], str) and len(locked[key]) == 64
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = materialize(Path(args.contract), Path(args.plan), Path(args.repo_root), args.production_base_sha)
    out = Path(args.output)
    out.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(
        "CORRECTED_FRAME_CROSSWALK_CANDIDATE_OK",
        f"rows={len(result['rows'])}",
        f"holds={len(result['multicell_hold_rows'])}",
        f"semantic={result['semantic_sha256']}",
    )


if __name__ == "__main__":
    main()
