#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import tempfile
from pathlib import Path

from build_road_destination_readiness_catalog import build_catalog

CELL_RE = re.compile(r"^bxl-e(\d+)-n(\d+)-s500$")


def load_json(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise RuntimeError(f"expected object: {path}")
    return data


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def semantic_sha(payload: dict) -> str:
    basis = dict(payload)
    basis.pop("production_base_sha", None)
    basis.pop("semantic_sha256", None)
    raw = json.dumps(basis, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(raw)


def grid_cell_id(cell_id: str) -> str:
    match = CELL_RE.fullmatch(cell_id)
    if not match:
        raise RuntimeError(f"invalid canonical cell id: {cell_id}")
    return f"E{match.group(1)}_N{match.group(2)}"


def require_all_false(mapping: dict, label: str) -> None:
    if not isinstance(mapping, dict) or not mapping:
        raise RuntimeError(f"missing authorization map: {label}")
    opened = {k: v for k, v in mapping.items() if v is not False}
    if opened:
        raise RuntimeError(f"authorization drift in {label}: {opened}")


def build_candidate_crosswalk(candidate: dict, registered_cell_semantic: str) -> dict:
    if candidate.get("schema") != "grand-bruxelles-corrected-frame-road-cell-crosswalk-materialization-candidate-v1":
        raise RuntimeError("corrected-frame crosswalk candidate schema drift")
    if candidate.get("status") != "CANDIDATE_EVIDENCE_ONLY_NOT_APPLIED":
        raise RuntimeError("corrected-frame crosswalk candidate status drift")
    require_all_false(candidate.get("authorization") or {}, "candidate crosswalk")
    policy = candidate.get("materialization_policy") or {}
    if policy.get("replace_current_crosswalk_authorized") is not False or policy.get("write_production_crosswalk_authorized") is not False:
        raise RuntimeError("candidate crosswalk replacement policy opened")

    rows = candidate.get("rows") or []
    seen = set()
    converted = []
    for row in rows:
        road_id = int(row["road_osm_id"])
        cell_id = str(row["cell_id"])
        if road_id in seen:
            raise RuntimeError(f"duplicate candidate road id: {road_id}")
        seen.add(road_id)
        converted.append({
            "road_osm_id": road_id,
            "cell_id": cell_id,
            "grid_cell_id": grid_cell_id(cell_id),
            "mapping_basis": "corrected_frame_unique_registered_cell_candidate",
            "mapping_evidence_only": True,
            "road_cell_mapping_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        })
    converted.sort(key=lambda row: row["road_osm_id"])
    cells = {row["cell_id"] for row in converted}
    return {
        "schema": "grand-bruxelles-road-registered-cell-crosswalk-v1",
        "destination_readiness": "CORRECTED_FRAME_CANDIDATE_EVIDENCE_ONLY",
        "mapping_policy": "corrected_frame_unique_registered_cell_candidate_only",
        "mapped_road_count": len(converted),
        "mapped_cell_count": len(cells),
        "registered_cell_index_semantic_sha256": registered_cell_semantic,
        "semantic_sha256": str(candidate["semantic_sha256"]),
        "road_cell_mapping_authorized": False,
        "runtime_directory_scan_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
        "rows": converted,
    }


def materialize(contract_path: Path, candidate_path: Path, repo_root: Path, production_base_sha: str) -> dict:
    contract = load_json(contract_path)
    if contract.get("schema") != "grand-bruxelles-corrected-frame-road-destination-readiness-candidate-contract-v1":
        raise RuntimeError("readiness candidate contract schema drift")
    if contract.get("status") not in {"MEASUREMENT_PENDING", "LOCKED_CANDIDATE_EVIDENCE_ONLY"}:
        raise RuntimeError("readiness candidate contract status drift")
    if contract.get("production_base_sha") != production_base_sha:
        raise RuntimeError("readiness candidate production base drift")
    require_all_false(contract.get("authorization") or {}, "readiness contract")
    policy = contract.get("policy") or {}
    if policy.get("artifact_only") is not True:
        raise RuntimeError("readiness candidate must be artifact-only")
    for key in ("replace_current_readiness_catalog_authorized", "replace_current_crosswalk_authorized", "runtime_probe_authorized"):
        if policy.get(key) is not False:
            raise RuntimeError(f"readiness policy opened: {key}")

    source = contract["source"]
    if source["provider"] != "OpenStreetMap contributors via Overpass API" or source["license"] != "ODbL-1.0" or source["crs"] != "EPSG:31370":
        raise RuntimeError("readiness provenance/CRS drift")

    materialization_contract = load_json(repo_root / source["crosswalk_materialization_contract_path"])
    if materialization_contract.get("status") != "LOCKED_CANDIDATE_EVIDENCE_ONLY":
        raise RuntimeError("corrected-frame crosswalk materialization is not locked")
    locked = materialization_contract["locked_evidence"]
    if int(locked["artifact_id"]) != int(source["crosswalk_candidate_artifact_id"]):
        raise RuntimeError("crosswalk candidate artifact id drift")
    if locked["artifact_sha256"] != source["crosswalk_candidate_artifact_sha256"]:
        raise RuntimeError("crosswalk candidate artifact sha drift")
    if locked["candidate_json_sha256"] != source["crosswalk_candidate_json_sha256"]:
        raise RuntimeError("crosswalk candidate json sha drift")
    if locked["semantic_sha256"] != source["crosswalk_candidate_semantic_sha256"]:
        raise RuntimeError("crosswalk candidate semantic drift")

    candidate_bytes = candidate_path.read_bytes()
    if sha256_bytes(candidate_bytes) != source["crosswalk_candidate_json_sha256"]:
        raise RuntimeError("restored crosswalk candidate bytes drift")
    candidate = json.loads(candidate_bytes)
    if candidate.get("semantic_sha256") != source["crosswalk_candidate_semantic_sha256"]:
        raise RuntimeError("restored crosswalk candidate semantic drift")

    cell_index_path = repo_root / source["registered_cell_index_path"]
    cell_index = load_json(cell_index_path)
    registered_cell_semantic = str(cell_index.get("semantic_sha256") or "")
    if len(registered_cell_semantic) != 64:
        raise RuntimeError("registered cell semantic digest missing")

    synthetic_crosswalk = build_candidate_crosswalk(candidate, registered_cell_semantic)
    expected = contract["expected"]
    if synthetic_crosswalk["mapped_road_count"] != int(expected["candidate_destination_count"]):
        raise RuntimeError("candidate destination accounting drift")
    if synthetic_crosswalk["mapped_cell_count"] != int(expected["candidate_mapped_cell_count"]):
        raise RuntimeError("candidate mapped cell accounting drift")
    holds = candidate.get("multicell_hold_rows") or []
    if len(holds) != int(expected["multicell_hold_count"]):
        raise RuntimeError("multicell hold accounting drift")
    if int(candidate["accounting"]["candidate_no_registered_overlap_count"]) != int(expected["no_registered_overlap_count"]):
        raise RuntimeError("no-overlap accounting drift")

    with tempfile.TemporaryDirectory() as temp_dir:
        crosswalk_path = Path(temp_dir) / "candidate-crosswalk.json"
        crosswalk_path.write_text(json.dumps(synthetic_crosswalk, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        catalog = build_catalog(
            repo_root,
            repo_root / source["road_runtime_index_path"],
            cell_index_path,
            crosswalk_path,
        )

    if catalog["destination_count"] != int(expected["candidate_destination_count"]):
        raise RuntimeError("readiness destination count drift")
    if catalog["mapped_cell_count"] != int(expected["candidate_mapped_cell_count"]):
        raise RuntimeError("readiness mapped cell count drift")
    require_all_false(catalog["authorization"], "generated readiness")
    by_id = {int(row["road_osm_id"]): row for row in catalog["destinations"]}
    if len(by_id) != len(catalog["destinations"]):
        raise RuntimeError("duplicate destination road id")
    for representative in expected["representatives"]:
        road_id = int(representative["road_osm_id"])
        expected_cell = representative["cell_id"]
        row = by_id.get(road_id)
        if row is None or row["cell_id"] != expected_cell:
            raise RuntimeError(f"representative target-cell mismatch: {road_id}")
        if row["readiness"] != "REGISTERED_NOT_RENDERED":
            raise RuntimeError(f"representative readiness drift: {road_id}")
        for key in ("render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"):
            if row[key] is not False:
                raise RuntimeError(f"representative runtime rail opened: {road_id} {key}")

    output = {
        "schema": "grand-bruxelles-corrected-frame-road-destination-readiness-candidate-v1",
        "status": "CANDIDATE_SOURCE_BACKED_REGISTERED_NOT_RENDERED",
        "production_base_sha": production_base_sha,
        "source": {
            "provider": source["provider"],
            "license": source["license"],
            "road_source_sha256": source["road_source_sha256"],
            "crosswalk_candidate_artifact_id": source["crosswalk_candidate_artifact_id"],
            "crosswalk_candidate_json_sha256": source["crosswalk_candidate_json_sha256"],
            "crosswalk_candidate_semantic_sha256": source["crosswalk_candidate_semantic_sha256"],
            "registered_cell_index_semantic_sha256": registered_cell_semantic,
            "crs": source["crs"],
        },
        "accounting": {
            "candidate_destination_count": catalog["destination_count"],
            "candidate_mapped_cell_count": catalog["mapped_cell_count"],
            "multicell_hold_count": len(holds),
            "no_registered_overlap_count": int(candidate["accounting"]["candidate_no_registered_overlap_count"]),
            "representative_target_cell_count": len(expected["representatives"]),
        },
        "destinations": catalog["destinations"],
        "multicell_hold_rows": holds,
        "policy": contract["policy"],
        "authorization": contract["authorization"],
    }
    output["semantic_sha256"] = semantic_sha(output)

    if contract["status"] == "LOCKED_CANDIDATE_EVIDENCE_ONLY":
        locked_out = contract["locked_evidence"]
        if output["semantic_sha256"] != locked_out["semantic_sha256"]:
            raise RuntimeError("locked readiness semantic drift")
        if output["accounting"] != locked_out["accounting"]:
            raise RuntimeError("locked readiness accounting drift")
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--crosswalk-candidate", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = materialize(Path(args.contract), Path(args.crosswalk_candidate), Path(args.repo_root), args.production_base_sha)
    out = Path(args.output)
    out.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(
        "CORRECTED_FRAME_READINESS_CANDIDATE_OK",
        f"destinations={result['accounting']['candidate_destination_count']}",
        f"cells={result['accounting']['candidate_mapped_cell_count']}",
        f"holds={result['accounting']['multicell_hold_count']}",
        f"semantic={result['semantic_sha256']}",
    )


if __name__ == "__main__":
    main()
