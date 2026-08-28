#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _canonical_sha(obj):
    return hashlib.sha256(
        json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ).hexdigest()


def _all_false(mapping):
    return isinstance(mapping, dict) and mapping and all(value is False for value in mapping.values())


def measure(
    contract_path: Path,
    impact_path: Path,
    repo_root: Path,
    production_base_sha: str,
    current_crosswalk_path: Path | None = None,
):
    contract = _load(contract_path)
    assert contract["schema"] == "grand-bruxelles-corrected-frame-road-cell-migration-plan-contract-v1"
    assert contract["status"] in {"MEASUREMENT_PENDING", "LOCKED_MIGRATION_PLAN_EVIDENCE_ONLY"}
    assert contract["production_base_sha"] == production_base_sha
    assert _all_false(contract["authorization"])
    assert contract["migration_policy"]["atomic_rebuild_required"] is True
    assert contract["migration_policy"]["replace_current_crosswalk_authorized"] is False
    assert contract["migration_policy"]["carry_old_mapping_without_reproof_authorized"] is False
    assert contract["migration_policy"]["multicell_mapping_authorized"] is False

    source = contract["source"]
    road_source = repo_root / source["road_source_path"]
    assert hashlib.sha256(road_source.read_bytes()).hexdigest() == source["road_source_sha256"]

    current_path = current_crosswalk_path or (repo_root / source["current_crosswalk_path"])
    current = _load(current_path)
    assert current["road_cell_mapping_authorized"] is False
    assert current["rendered_geometry_authorized"] is False
    assert current["collision_authorized"] is False
    assert current["jouable_promotion_authorized"] is False
    current_rows = current["rows"]
    current_by_id = {int(row["road_osm_id"]): row["cell_id"] for row in current_rows}
    assert len(current_by_id) == len(current_rows), "duplicate current road mapping"

    candidate_contract = _load(repo_root / source["candidate_contract_path"])
    assert candidate_contract["semantic_sha256"] == source["candidate_semantic_sha256"]
    assert candidate_contract["promotion_policy"]["replace_current_crosswalk_authorized"] is False
    assert _all_false(candidate_contract["authorization"])

    impact = _load(impact_path)
    assert impact["semantic_sha256"] == source["impact_stable_semantic_sha256"]
    candidate_rows = impact["candidate_unique_rows"]
    candidate_by_id = {int(row["road_osm_id"]): row["cell_id"] for row in candidate_rows}
    assert len(candidate_by_id) == len(candidate_rows), "duplicate candidate road mapping"

    hold_rows = impact["candidate_multicell_rows"]
    hold_ids = {int(row["road_osm_id"]) for row in hold_rows}
    assert not (set(candidate_by_id) & hold_ids), "multicell road leaked into unique candidate"

    retained = []
    changed = []
    newly = []
    removed = []
    for road_id in sorted(set(current_by_id) | set(candidate_by_id)):
        old = current_by_id.get(road_id)
        new = candidate_by_id.get(road_id)
        if old is not None and new is not None:
            row = {"road_osm_id": road_id, "current_cell_id": old, "candidate_cell_id": new}
            (retained if old == new else changed).append(row)
        elif new is not None:
            newly.append({"road_osm_id": road_id, "candidate_cell_id": new})
        else:
            removed.append({"road_osm_id": road_id, "current_cell_id": old})

    accounting = {
        "source_road_count": impact["accounting"]["source_road_count"],
        "current_mapped_road_count": len(current_by_id),
        "candidate_unique_mapped_road_count": len(candidate_by_id),
        "candidate_multicell_road_count": len(hold_rows),
        "candidate_no_registered_overlap_count": impact["accounting"]["candidate_no_registered_overlap_count"],
        "retained_mapping_count": len(retained),
        "changed_mapping_count": len(changed),
        "newly_mappable_count": len(newly),
        "no_longer_mappable_count": len(removed),
    }
    assert accounting == contract["expected"], (accounting, contract["expected"])

    output = {
        "schema": "grand-bruxelles-corrected-frame-road-cell-migration-plan-v1",
        "status": "MIGRATION_PLAN_EVIDENCE_ONLY",
        "production_base_sha": production_base_sha,
        "source": {
            "provider": source["provider"],
            "license": source["license"],
            "road_source_sha256": source["road_source_sha256"],
            "candidate_semantic_sha256": source["candidate_semantic_sha256"],
            "impact_stable_semantic_sha256": source["impact_stable_semantic_sha256"],
            "crs": source["crs"],
            "origin_easting_m": source["origin_easting_m"],
            "origin_northing_m": source["origin_northing_m"],
            "formula": source["formula"],
        },
        "accounting": accounting,
        "retained_rows": retained,
        "changed_rows": changed,
        "newly_mappable_rows": newly,
        "no_longer_mappable_rows": removed,
        "multicell_hold_rows": hold_rows,
        "migration_policy": contract["migration_policy"],
        "authorization": contract["authorization"],
    }
    basis = dict(output)
    basis.pop("production_base_sha")
    output["semantic_sha256"] = _canonical_sha(basis)

    if contract["status"] == "LOCKED_MIGRATION_PLAN_EVIDENCE_ONLY":
        locked = contract["locked_evidence"]
        assert locked["semantic_sha256"] == output["semantic_sha256"]
        assert locked["accounting"] == accounting
        assert isinstance(locked["workflow_run_id"], int) and locked["workflow_run_id"] > 0
        assert isinstance(locked["artifact_id"], int) and locked["artifact_id"] > 0
        for key in ("artifact_sha256", "measurement_json_sha256", "semantic_sha256"):
            value = locked[key]
            assert isinstance(value, str) and len(value) == 64
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--impact", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--current-crosswalk")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = measure(
        Path(args.contract),
        Path(args.impact),
        Path(args.repo_root),
        args.production_base_sha,
        Path(args.current_crosswalk) if args.current_crosswalk else None,
    )
    out = Path(args.output)
    out.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(
        "CORRECTED_FRAME_ROAD_CELL_MIGRATION_PLAN_OK",
        f"changed={result['accounting']['changed_mapping_count']}",
        f"new={result['accounting']['newly_mappable_count']}",
        f"removed={result['accounting']['no_longer_mappable_count']}",
        f"holds={result['accounting']['candidate_multicell_road_count']}",
        f"semantic={result['semantic_sha256']}",
    )


if __name__ == "__main__":
    main()
