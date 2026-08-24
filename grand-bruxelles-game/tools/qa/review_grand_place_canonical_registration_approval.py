#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

CELL_ID = "bxl-e148000-n170000-s500"
CRS = "EPSG:31370"
BBOX = [148000.0, 170000.0, 148500.0, 170500.0]

CANDIDATE_REVIEW_PATH = Path("data/provenance/grand_place_canonical_manifest_candidate.review.json")
REGISTRATION_REVIEW_PATH = Path("data/provenance/grand_place_cell_registration.review.json")
SOURCE_LOCK_PATH = Path("data/provenance/grand_place_urbis_source_cell.measurement.json")
REGISTERED_INDEX_PATH = Path("data/provenance/brussels_registered_cell_manifest_index.json")
CANONICAL_PATH = Path("data/cell_manifests/bxl-e148000-n170000-s500.json")
SOURCE_MANIFEST_PATH = Path("data/urbis/remaining_brussels/cells/bxl-e148000-n170000-s500/manifest.json")

CANDIDATE_REVIEW_SHA = "bb0a23818b738b22b20aea1d9c37ecf794827e05d5d4ab8fed4f758d0c6f197e"
CANDIDATE_SHA = "b454022050e850214eeb8d5345fe574e831dcaba6a832123a7dfe44070d0b020"
REGISTRATION_REVIEW_SHA = "b84398dd084e85dce7e065ebd3fc87f873dcf965edb48ba55ea1eae519e61565"
SOURCE_MANIFEST_SHA = "4c18e124adfbdb230fcd357c444f58c1d532db2812f77d6f97380676f60e00c7"
SOURCE_DIGEST = "bbee45393ca07d86515f160e6eb9511c624440ccced97dff564b133eeafe7feb"
SOURCE_SEMANTIC_SHA = "99cb25db4c95860c02dff5cf25c19cc5a4e11a75166f1fe92734edd1b5a0e7d4"
REGISTERED_INDEX_SHA = "606c57c18fac82bcd74b4bb870e37d89ff31c775b3fa57533559c17d7a75de6f"
MUNICIPALITY_ID = "https://databrussels.be/id/municipality/5000074"
MUNICIPALITY_NIS = "21004"

CANDIDATE_RAILS = [
    "canonical_manifest_write",
    "collision",
    "jouable_promotion",
    "registered_index_mutation",
    "rendered_geometry",
    "road_to_cell_mapping",
    "runtime_mount",
    "safe_spawn",
]
REGISTRATION_RAILS = [
    "registration_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
]
INDEX_RAILS = [
    "collision_authorized",
    "jouable_promotion_authorized",
    "rendered_geometry_authorized",
    "road_crosswalk_authorized",
    "runtime_directory_scan_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
]
CLOSED_APPROVAL_RAILS = [
    "road_to_cell_mapping",
    "runtime_directory_scan",
    "runtime_mount",
    "rendered_geometry",
    "collision",
    "safe_spawn",
    "jouable_promotion",
]


def _load(root: Path, rel: Path) -> dict[str, Any]:
    path = root / rel
    if not path.is_file():
        raise RuntimeError(f"required evidence missing: {rel.as_posix()}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"invalid evidence JSON: {rel.as_posix()}: {exc}") from exc
    if not isinstance(payload, dict):
        raise RuntimeError(f"evidence root must be an object: {rel.as_posix()}")
    return payload


def _require(value: Any, expected: Any, label: str) -> None:
    if value != expected:
        raise RuntimeError(f"{label} drift: {value!r} != {expected!r}")


def _require_closed(payload: dict[str, Any], keys: list[str], label: str) -> None:
    for key in keys:
        if payload.get(key) is not False:
            raise RuntimeError(f"{label} rail opened: {key}")


def _sha256_json(payload: dict[str, Any]) -> str:
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def _validate_sha(value: Any, label: str) -> str:
    text = str(value)
    if re.fullmatch(r"[0-9a-f]{64}", text) is None:
        raise RuntimeError(f"{label} must be lowercase SHA-256")
    return text


def review(repo_root: Path, production_base_sha: str) -> dict[str, Any]:
    if re.fullmatch(r"[0-9a-f]{40}", production_base_sha) is None:
        raise RuntimeError("production base must be a lowercase 40-hex Git SHA")
    if (repo_root / CANONICAL_PATH).exists():
        raise RuntimeError("canonical manifest already exists")

    candidate = _load(repo_root, CANDIDATE_REVIEW_PATH)
    registration = _load(repo_root, REGISTRATION_REVIEW_PATH)
    source_lock = _load(repo_root, SOURCE_LOCK_PATH)
    index = _load(repo_root, REGISTERED_INDEX_PATH)

    _require(candidate.get("schema"), "grand-bruxelles-grand-place-canonical-manifest-candidate-review-v1", "candidate schema")
    _require(candidate.get("status"), "CANDIDATE_LOCKED_UNREGISTERED", "candidate status")
    _require(_validate_sha(candidate.get("semantic_sha256"), "candidate semantic SHA"), CANDIDATE_REVIEW_SHA, "candidate semantic SHA")
    target = candidate.get("target") or {}
    _require(target.get("cell_id"), CELL_ID, "candidate cell")
    _require(target.get("crs"), CRS, "candidate CRS")
    _require(target.get("bbox"), BBOX, "candidate bbox")
    _require(target.get("canonical_manifest_path"), CANONICAL_PATH.as_posix(), "candidate canonical path")
    _require(target.get("canonical_manifest_present"), False, "candidate canonical presence")
    manifest = candidate.get("candidate_manifest") or {}
    _require(_validate_sha(manifest.get("sha256"), "candidate manifest SHA"), CANDIDATE_SHA, "candidate manifest SHA")
    _require(manifest.get("format"), "grand-bruxelles-cell-maturity-v1", "candidate format")
    _require(manifest.get("maturity_state"), "data_ready", "candidate maturity")
    _require(manifest.get("all_maturity_gates_false"), True, "candidate maturity gates")
    _require_closed(candidate.get("authorization") or {}, CANDIDATE_RAILS, "candidate")

    candidate_index = candidate.get("registered_cell_index") or {}
    _require(candidate_index.get("registered_cell_count"), 1, "candidate index count")
    _require(candidate_index.get("target_registered"), False, "candidate target registration")
    candidate_registration = candidate.get("registration_review") or {}
    _require(candidate_registration.get("status"), "READY_FOR_CANONICAL_MANIFEST_REVIEW", "candidate registration-review status")
    _require(_validate_sha(candidate_registration.get("semantic_sha256"), "candidate registration-review SHA"), REGISTRATION_REVIEW_SHA, "candidate registration-review SHA")
    source_evidence = candidate.get("source_evidence") or {}
    _require(source_evidence.get("authority"), "Paradigm / Brussels-Capital Region", "candidate source authority")
    _require(source_evidence.get("license"), "CC0-1.0", "candidate source license")
    _require(_validate_sha(source_evidence.get("source_manifest_sha256"), "candidate source-manifest SHA"), SOURCE_MANIFEST_SHA, "candidate source-manifest SHA")
    _require(_validate_sha(source_evidence.get("source_digest"), "candidate source digest"), SOURCE_DIGEST, "candidate source digest")
    _require(_validate_sha(source_evidence.get("source_semantic_sha256"), "candidate source semantic SHA"), SOURCE_SEMANTIC_SHA, "candidate source semantic SHA")

    _require(registration.get("schema"), "grand-bruxelles-grand-place-cell-registration-review-v1", "registration-review schema")
    _require(registration.get("status"), "READY_FOR_CANONICAL_MANIFEST_REVIEW", "registration-review status")
    _require(_validate_sha(registration.get("semantic_sha256"), "registration-review semantic SHA"), REGISTRATION_REVIEW_SHA, "registration-review semantic SHA")
    reg_target = registration.get("target") or {}
    _require(reg_target.get("cell_id"), CELL_ID, "registration-review cell")
    _require(reg_target.get("crs"), CRS, "registration-review CRS")
    _require(reg_target.get("bbox"), BBOX, "registration-review bbox")
    _require(reg_target.get("canonical_manifest_path"), CANONICAL_PATH.as_posix(), "registration-review canonical path")
    _require(reg_target.get("canonical_manifest_present"), False, "registration-review canonical presence")
    _require(reg_target.get("authoritative_source_manifest_present"), True, "registration-review source presence")
    municipality = registration.get("municipality_evidence") or {}
    _require(municipality.get("municipality_id"), MUNICIPALITY_ID, "municipality INSPIRE id")
    _require(str(municipality.get("municipality_niscode")), MUNICIPALITY_NIS, "municipality NIS")
    _require(municipality.get("coverage_ratio"), 1.0, "municipality coverage")
    _require(municipality.get("road_ids"), [13842686, 684214770], "municipality road ids")
    _require(municipality.get("point_hits"), 9, "municipality point hits")
    _require(municipality.get("segment_hits"), 7, "municipality segment hits")
    registration_index = registration.get("registered_cell_index") or {}
    _require(_validate_sha(registration_index.get("semantic_sha256"), "registration index SHA"), REGISTERED_INDEX_SHA, "registration index SHA")
    _require(registration_index.get("registered_cell_count"), 1, "registration index count")
    _require(registration_index.get("target_already_registered"), False, "registration target already registered")
    authoritative = registration.get("authoritative_source_evidence") or {}
    _require(_validate_sha(authoritative.get("manifest_sha256"), "registration source-manifest SHA"), SOURCE_MANIFEST_SHA, "registration source-manifest SHA")
    _require(_validate_sha(authoritative.get("source_digest"), "registration source digest"), SOURCE_DIGEST, "registration source digest")
    _require(authoritative.get("format"), "grand-bruxelles-urbis-source-cell-v1", "registration source format")
    _require(authoritative.get("promotion"), "source_only_no_runtime_mutation", "registration source promotion")
    _require(authoritative.get("layer_feature_counts"), {
        "buildings": 772,
        "street_axes": 97,
        "street_surfaces": 410,
        "train_network": 28,
        "tram_network": 28,
    }, "registration source accounting")
    _require(authoritative.get("buildings_ownership_filtered"), 61, "registration filtered ownership")
    _require(authoritative.get("buildings_invalid_ownership_features"), 0, "registration invalid ownership")
    _require_closed(registration, REGISTRATION_RAILS, "registration review")

    _require(source_lock.get("schema"), "grand-bruxelles-urbis-source-cell-lock-v2", "source-lock schema")
    _require(source_lock.get("status"), "LOCKED_EXACT_SOURCE_ONLY_PERSISTED", "source-lock status")
    source_target = source_lock.get("target") or {}
    _require(source_target.get("cell_id"), CELL_ID, "source-lock cell")
    _require(source_target.get("crs"), CRS, "source-lock CRS")
    _require(source_target.get("bbox"), BBOX, "source-lock bbox")
    source = source_lock.get("source") or {}
    _require(source.get("authority"), "Paradigm / Brussels-Capital Region", "source-lock authority")
    _require(source.get("license"), "CC0-1.0", "source-lock license")
    locked = source_lock.get("locked") or {}
    _require(_validate_sha(locked.get("manifest_source_digest"), "source-lock manifest digest"), SOURCE_DIGEST, "source-lock manifest digest")
    _require(_validate_sha(locked.get("source_semantic_sha256"), "source-lock semantic SHA"), SOURCE_SEMANTIC_SHA, "source-lock semantic SHA")
    persisted = ((source_lock.get("persisted_artifact_bytes") or {}).get("persistence") or {})
    _require(_validate_sha(persisted.get("manifest_sha256"), "persisted source-manifest SHA"), SOURCE_MANIFEST_SHA, "persisted source-manifest SHA")
    _require(_validate_sha(persisted.get("source_semantic_sha256"), "persisted source semantic SHA"), SOURCE_SEMANTIC_SHA, "persisted source semantic SHA")
    source_auth = source_lock.get("authorization") or {}
    _require(source_auth.get("source_acquisition"), True, "source acquisition authorization")
    for key in ["source_registration", "canonical_registration", "road_to_cell_mapping", "runtime_mount", "rendered_geometry", "collision", "safe_spawn", "jouable_promotion"]:
        if source_auth.get(key) is not False:
            raise RuntimeError(f"source-lock rail opened: {key}")

    _require(index.get("schema"), "grand-bruxelles-registered-cell-manifest-index-v1", "registered index schema")
    _require(_validate_sha(index.get("semantic_sha256"), "registered index semantic SHA"), REGISTERED_INDEX_SHA, "registered index semantic SHA")
    _require(index.get("destination_readiness"), "REGISTERED_CELL_INDEX_EVIDENCE_ONLY", "registered index readiness")
    _require(index.get("registered_cell_count"), 1, "registered index count")
    _require_closed(index, INDEX_RAILS, "registered-cell index")
    entries = index.get("entries")
    if not isinstance(entries, list) or len(entries) != 1:
        raise RuntimeError("registered-cell index accounting drift")
    if any(isinstance(row, dict) and row.get("cell_id") == CELL_ID for row in entries):
        raise RuntimeError("target cell already registered")

    stable = {
        "schema": "grand-bruxelles-grand-place-canonical-registration-approval-v1",
        "status": "APPROVED_EVIDENCE_ONLY_CANONICAL_REGISTRATION",
        "target": {
            "cell_id": CELL_ID,
            "crs": CRS,
            "bbox": BBOX,
            "canonical_manifest_path": CANONICAL_PATH.as_posix(),
            "canonical_manifest_present": False,
        },
        "candidate": {
            "review_semantic_sha256": CANDIDATE_REVIEW_SHA,
            "manifest_sha256": CANDIDATE_SHA,
        },
        "registration_review": {
            "semantic_sha256": REGISTRATION_REVIEW_SHA,
            "status": "READY_FOR_CANONICAL_MANIFEST_REVIEW",
        },
        "source": {
            "authority": "Paradigm / Brussels-Capital Region",
            "license": "CC0-1.0",
            "manifest_sha256": SOURCE_MANIFEST_SHA,
            "source_digest": SOURCE_DIGEST,
            "source_semantic_sha256": SOURCE_SEMANTIC_SHA,
        },
        "registered_cell_index": {
            "semantic_sha256": REGISTERED_INDEX_SHA,
            "registered_cell_count": 1,
            "target_registered": False,
        },
        "authorization": {
            "canonical_manifest_write": True,
            "registered_index_mutation": True,
            "evidence_only_registration": True,
            "road_to_cell_mapping": False,
            "runtime_directory_scan": False,
            "runtime_mount": False,
            "rendered_geometry": False,
            "collision": False,
            "safe_spawn": False,
            "jouable_promotion": False,
        },
        "destination_readiness": "APPROVED_FOR_EVIDENCE_ONLY_REGISTRATION_NOT_RENDERED",
    }
    result = dict(stable)
    result["production_base_sha"] = production_base_sha
    result["semantic_sha256"] = _sha256_json(stable)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--out-review", type=Path, required=True)
    args = parser.parse_args()
    result = review(args.repo_root, args.production_base_sha)
    args.out_review.parent.mkdir(parents=True, exist_ok=True)
    args.out_review.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "GRAND_PLACE_CANONICAL_REGISTRATION_APPROVAL_OK: "
        f"cell={CELL_ID} base={args.production_base_sha} semantic={result['semantic_sha256']} "
        "registration=evidence-only runtime=false jouable=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
