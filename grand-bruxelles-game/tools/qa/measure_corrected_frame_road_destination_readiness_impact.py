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


def _current_destinations(readiness):
    assert readiness["destination_count"] == len(readiness["destinations"])
    assert _all_false(readiness["authorization"])
    rows = {}
    for row in readiness["destinations"]:
        road_id = int(row["road_osm_id"])
        assert row["destination_id"] == f"road-{road_id}"
        assert row["readiness"] == "REGISTERED_NOT_RENDERED"
        for key in ("render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"):
            assert row[key] is False
        assert road_id not in rows
        rows[road_id] = row
    return rows


def measure(contract_path: Path, candidate_path: Path, readiness_path: Path, production_base_sha: str):
    contract = _load(contract_path)
    assert contract["schema"] == "grand-bruxelles-corrected-frame-road-destination-readiness-impact-contract-v1"
    assert contract["status"] in {"MEASUREMENT_PENDING", "LOCKED_IMPACT_EVIDENCE_ONLY"}
    assert contract["production_base_sha"] == production_base_sha
    assert _all_false(contract["authorization"])
    policy = contract["policy"]
    assert policy["measurement_only"] is True
    assert policy["replace_readiness_catalog_authorized"] is False
    assert policy["replace_crosswalk_authorized"] is False
    assert policy["multicell_destination_authorized"] is False
    assert policy["atomic_followup_required"] is True

    candidate = _load(candidate_path)
    assert candidate["schema"] == "grand-bruxelles-corrected-frame-road-cell-crosswalk-materialization-candidate-v1"
    assert candidate["status"] == "CANDIDATE_EVIDENCE_ONLY_NOT_APPLIED"
    assert candidate["semantic_sha256"] == contract["source"]["materialization_semantic_sha256"]
    assert _all_false(candidate["authorization"])
    assert candidate["materialization_policy"]["replace_current_crosswalk_authorized"] is False
    assert candidate["materialization_policy"]["write_production_crosswalk_authorized"] is False
    assert candidate["materialization_policy"]["multicell_mapping_authorized"] is False

    readiness = _load(readiness_path)
    current = _current_destinations(readiness)
    candidate_rows = {}
    for row in candidate["rows"]:
        road_id = int(row["road_osm_id"])
        assert road_id not in candidate_rows
        candidate_rows[road_id] = row["cell_id"]

    hold_ids = {int(row["road_osm_id"]) for row in candidate["multicell_hold_rows"]}
    assert not (hold_ids & set(candidate_rows))

    current_ids = set(current)
    candidate_ids = set(candidate_rows)
    common_ids = current_ids & candidate_ids
    retained = sorted(
        road_id for road_id in common_ids if current[road_id]["cell_id"] == candidate_rows[road_id]
    )
    changed = sorted(
        road_id for road_id in common_ids if current[road_id]["cell_id"] != candidate_rows[road_id]
    )
    new = sorted(candidate_ids - current_ids)
    removed = sorted(current_ids - candidate_ids)

    changed_rows = [
        {
            "road_osm_id": road_id,
            "destination_id": f"road-{road_id}",
            "current_cell_id": current[road_id]["cell_id"],
            "candidate_cell_id": candidate_rows[road_id],
        }
        for road_id in changed
    ]
    retained_rows = [
        {
            "road_osm_id": road_id,
            "destination_id": f"road-{road_id}",
            "cell_id": candidate_rows[road_id],
        }
        for road_id in retained
    ]
    new_rows = [
        {
            "road_osm_id": road_id,
            "destination_id": f"road-{road_id}",
            "candidate_cell_id": candidate_rows[road_id],
        }
        for road_id in new
    ]
    removed_rows = [
        {
            "road_osm_id": road_id,
            "destination_id": f"road-{road_id}",
            "current_cell_id": current[road_id]["cell_id"],
        }
        for road_id in removed
    ]

    accounting = {
        "current_destination_count": len(current),
        "candidate_unique_destination_count": len(candidate_rows),
        "multicell_hold_count": len(hold_ids),
        "no_registered_overlap_count": candidate["accounting"]["candidate_no_registered_overlap_count"],
        "retained_destination_count": len(retained_rows),
        "changed_cell_destination_count": len(changed_rows),
        "new_destination_count": len(new_rows),
        "removed_destination_count": len(removed_rows),
    }
    assert accounting == contract["expected"]

    output = {
        "schema": "grand-bruxelles-corrected-frame-road-destination-readiness-impact-v1",
        "status": "IMPACT_EVIDENCE_ONLY_NOT_APPLIED",
        "production_base_sha": production_base_sha,
        "source": {
            "provider": contract["source"]["provider"],
            "license": contract["source"]["license"],
            "road_source_sha256": contract["source"]["road_source_sha256"],
            "materialization_semantic_sha256": candidate["semantic_sha256"],
            "current_readiness_catalog_sha256": _sha256(readiness_path),
            "crs": contract["source"]["crs"],
        },
        "accounting": accounting,
        "retained_rows": retained_rows,
        "changed_rows": changed_rows,
        "new_rows": new_rows,
        "removed_rows": removed_rows,
        "multicell_hold_road_ids": sorted(hold_ids),
        "policy": policy,
        "authorization": contract["authorization"],
    }
    basis = dict(output)
    basis.pop("production_base_sha")
    output["semantic_sha256"] = _canonical_sha(basis)

    if contract["status"] == "LOCKED_IMPACT_EVIDENCE_ONLY":
        locked = contract["locked_evidence"]
        assert locked["semantic_sha256"] == output["semantic_sha256"]
        assert locked["accounting"] == accounting
        for key in ("artifact_sha256", "measurement_sha256", "semantic_sha256"):
            assert isinstance(locked[key], str) and len(locked[key]) == 64
        assert isinstance(locked["artifact_id"], int) and locked["artifact_id"] > 0
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--readiness", required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = measure(
        Path(args.contract), Path(args.candidate), Path(args.readiness), args.production_base_sha
    )
    out = Path(args.output)
    out.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(
        "CORRECTED_FRAME_DESTINATION_IMPACT_OK",
        f"current={result['accounting']['current_destination_count']}",
        f"candidate={result['accounting']['candidate_unique_destination_count']}",
        f"changed={result['accounting']['changed_cell_destination_count']}",
        f"new={result['accounting']['new_destination_count']}",
        f"removed={result['accounting']['removed_destination_count']}",
        f"semantic={result['semantic_sha256']}",
    )


if __name__ == "__main__":
    main()
