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
    return hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def _all_false(mapping):
    return isinstance(mapping, dict) and mapping and all(v is False for v in mapping.values())


def _roads_by_id(source):
    roads = {}
    for road in source["roads"]:
        road_id = int(road["osm_id"])
        assert road_id not in roads
        roads[road_id] = road
    return roads


def _validate_live_main_replay(contract, production_base_sha):
    evidence_base = contract["production_base_sha"]
    if evidence_base == production_base_sha:
        return
    assert contract["status"] == "LOCKED_REPRESENTATIVE_EVIDENCE_ONLY"
    assert contract.get("continuity", {}).get("semantic_lock_survives_clean_live_main_rebuild") is True
    locked = contract.get("locked_evidence")
    assert isinstance(locked, dict)
    assert isinstance(locked.get("semantic_sha256"), str) and len(locked["semantic_sha256"]) == 64
    assert isinstance(locked.get("measurement_sha256"), str) and len(locked["measurement_sha256"]) == 64
    assert locked.get("accounting") == contract["expected"]
    assert locked.get("selected_road_osm_ids") == [int(t["expected_road_osm_id"]) for t in contract["selection"]["target_cells"]]


def measure(contract_path: Path, impact_path: Path, road_source_path: Path, cell_index_path: Path, production_base_sha: str):
    contract = _load(contract_path)
    assert contract["schema"] == "grand-bruxelles-corrected-frame-corridor-representative-contract-v1"
    assert contract["status"] in {"MEASUREMENT_PENDING", "LOCKED_REPRESENTATIVE_EVIDENCE_ONLY"}
    _validate_live_main_replay(contract, production_base_sha)
    assert contract["source"]["provider"] == "OpenStreetMap contributors via Overpass API"
    assert contract["source"]["license"] == "ODbL-1.0"
    assert contract["source"]["crs"] == "EPSG:31370"
    assert _all_false(contract["authorization"])
    assert contract["policy"]["measurement_only"] is True
    assert contract["policy"]["replace_crosswalk_authorized"] is False
    assert contract["policy"]["replace_readiness_catalog_authorized"] is False
    assert contract["policy"]["representative_runtime_probe_authorized"] is False

    impact = _load(impact_path)
    assert impact["schema"] == "grand-bruxelles-corrected-frame-road-destination-readiness-impact-v1"
    assert impact["status"] == "IMPACT_EVIDENCE_ONLY_NOT_APPLIED"
    assert impact["semantic_sha256"] == contract["source"]["impact_semantic_sha256"]
    assert _all_false(impact["authorization"])

    assert _sha256(road_source_path) == contract["source"]["road_source_sha256"]
    road_source = _load(road_source_path)
    assert road_source["source"] == contract["source"]["provider"]
    assert road_source["license"] == contract["source"]["license"]
    roads = _roads_by_id(road_source)

    cell_index = _load(cell_index_path)
    assert cell_index["schema"] == "grand-bruxelles-registered-cell-manifest-index-v1"
    assert cell_index["semantic_sha256"] == contract["source"]["registered_cell_index_semantic_sha256"]
    for key in ("road_crosswalk_authorized", "runtime_directory_scan_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"):
        assert cell_index[key] is False
    cells = {row["cell_id"]: row for row in cell_index["entries"]}
    assert len(cells) == cell_index["registered_cell_count"]
    for row in cells.values():
        assert row["crs"] == "EPSG:31370"
        assert row["maturity_state"] == "data_ready"
        assert row["evidence_only"] is True
        for key in ("runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"):
            assert row[key] is False

    changed_by_cell = {}
    for row in impact["changed_rows"]:
        changed_by_cell.setdefault(row["candidate_cell_id"], []).append(row)
    new_by_cell = {}
    for row in impact["new_rows"]:
        new_by_cell.setdefault(row["candidate_cell_id"], []).append(row)

    representatives = []
    for target in contract["selection"]["target_cells"]:
        cell_id = target["cell_id"]
        assert cell_id in cells
        changed = sorted(changed_by_cell.get(cell_id, []), key=lambda r: int(r["road_osm_id"]))
        new = sorted(new_by_cell.get(cell_id, []), key=lambda r: int(r["road_osm_id"]))
        if changed:
            transition, picked = "changed", changed[0]
        else:
            assert new
            transition, picked = "new", new[0]
        road_id = int(picked["road_osm_id"])
        expected_destination_id = f"road-{road_id}"
        assert picked.get("destination_id") == expected_destination_id
        assert transition == target["expected_transition"]
        assert road_id == int(target["expected_road_osm_id"])
        assert road_id in roads
        road = roads[road_id]
        assert road["drivable"] is True
        assert isinstance(road["points"], list) and len(road["points"]) >= 2
        representative = {
            "anchor": target["anchor"],
            "transition": transition,
            "road_osm_id": road_id,
            "destination_id": picked["destination_id"],
            "candidate_cell_id": cell_id,
            "current_cell_id": picked.get("current_cell_id"),
            "road_name": road["name"],
            "road_class": road["class"],
            "road_width_m": road["width"],
            "source_point_count": len(road["points"]),
            "source_road_semantic_sha256": _canonical_sha(road),
            "registered_cell": {
                "manifest_path": cells[cell_id]["manifest_path"],
                "manifest_sha256": cells[cell_id]["manifest_sha256"],
                "bbox": cells[cell_id]["bbox"],
                "maturity_state": cells[cell_id]["maturity_state"]
            }
        }
        if transition == "new":
            assert representative["current_cell_id"] is None
        else:
            assert isinstance(representative["current_cell_id"], str) and representative["current_cell_id"] != cell_id
        representatives.append(representative)

    accounting = {
        "representative_count": len(representatives),
        "changed_count": sum(r["transition"] == "changed" for r in representatives),
        "new_count": sum(r["transition"] == "new" for r in representatives)
    }
    assert accounting == contract["expected"]
    assert len({r["road_osm_id"] for r in representatives}) == len(representatives)
    assert len({r["candidate_cell_id"] for r in representatives}) == len(representatives)

    output = {
        "schema": "grand-bruxelles-corrected-frame-corridor-representative-v1",
        "status": "REPRESENTATIVE_EVIDENCE_ONLY_NOT_APPLIED",
        "production_base_sha": production_base_sha,
        "source": {
            "provider": contract["source"]["provider"],
            "license": contract["source"]["license"],
            "road_source_sha256": contract["source"]["road_source_sha256"],
            "impact_semantic_sha256": impact["semantic_sha256"],
            "registered_cell_index_semantic_sha256": cell_index["semantic_sha256"],
            "crs": contract["source"]["crs"]
        },
        "selection_policy": contract["selection"]["policy"],
        "accounting": accounting,
        "representatives": representatives,
        "policy": contract["policy"],
        "authorization": contract["authorization"]
    }
    basis = dict(output)
    basis.pop("production_base_sha")
    output["semantic_sha256"] = _canonical_sha(basis)

    if contract["status"] == "LOCKED_REPRESENTATIVE_EVIDENCE_ONLY":
        locked = contract["locked_evidence"]
        assert locked["semantic_sha256"] == output["semantic_sha256"]
        assert locked["accounting"] == accounting
        assert locked["selected_road_osm_ids"] == [r["road_osm_id"] for r in representatives]
    return output


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--contract", required=True)
    p.add_argument("--impact", required=True)
    p.add_argument("--road-source", required=True)
    p.add_argument("--cell-index", required=True)
    p.add_argument("--production-base-sha", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args()
    result = measure(Path(a.contract), Path(a.impact), Path(a.road_source), Path(a.cell_index), a.production_base_sha)
    Path(a.output).write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print("CORRIDOR_REPRESENTATIVES_OK", result["accounting"], result["semantic_sha256"])


if __name__ == "__main__":
    main()
