#!/usr/bin/env python3
"""Build a deterministic fail-closed road destination index from a locked source artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import zipfile
from pathlib import Path

MANIFEST_MEMBER = "auderghem.manifest.json"
RAW_MEMBER = "auderghem_road_source.raw.json"
GAME_MEMBER = "auderghem_road_source.game.json"
RECEIPT_MEMBER = "auderghem_road_source.receipt.json"
REQUIRED_MEMBERS = (MANIFEST_MEMBER, RAW_MEMBER, GAME_MEMBER, RECEIPT_MEMBER)
DOWNSTREAM_KEYS = (
    "source_registration_authorized",
    "road_cell_mapping_authorized",
    "render_authorized",
    "collision_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
    "jouable_authorized",
)
DOWNSTREAM_KEY_SET = frozenset(DOWNSTREAM_KEYS)
MANIFEST_AUTHORIZATION_KEY_SET = DOWNSTREAM_KEY_SET | {"source_acquisition_authorized"}
EVIDENCE_FORMAT = "grand-bruxelles-missing-road-source-acquisition-evidence-v1"


def _no_duplicate_keys(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key: {key}")
        out[key] = value
    return out


def _load_json(raw: bytes, member: str):
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=_no_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise ValueError(f"invalid JSON member {member}: {exc}") from exc


def _canonical_json_sha256(value) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _valid_sha256(value) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(ch in "0123456789abcdef" for ch in value)


def _finite_number(value, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{label} must be a finite number")
    return float(value)


def _checked_bounds(value, label: str) -> list[float]:
    if not isinstance(value, list) or len(value) != 4:
        raise ValueError(f"{label} must be [min_x,min_z,max_x,max_z]")
    checked = [_finite_number(item, f"{label}[{index}]") for index, item in enumerate(value)]
    if checked[0] > checked[2] or checked[1] > checked[3]:
        raise ValueError(f"{label} is inverted")
    if checked[0] == checked[2] or checked[1] == checked[3]:
        raise ValueError(f"{label} is degenerate")
    return checked


def _require_exact_authorization(value, expected_keys, label: str):
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    actual = set(value)
    if actual != set(expected_keys):
        missing = sorted(set(expected_keys) - actual)
        unexpected = sorted(actual - set(expected_keys))
        raise ValueError(f"{label} schema mismatch: missing={missing} unexpected={unexpected}")
    return value


def _locked_artifact_selection(evidence_lock: Path, municipality_nis: str):
    evidence = _load_json(evidence_lock.read_bytes(), str(evidence_lock))
    if not isinstance(evidence, dict) or evidence.get("format") != EVIDENCE_FORMAT:
        raise ValueError("unexpected acquisition evidence lock format")
    successful = evidence.get("successful_acquisitions")
    if not isinstance(successful, list):
        raise ValueError("invalid acquisition evidence successful_acquisitions")
    matches = [row for row in successful if isinstance(row, dict) and row.get("niscode") == municipality_nis]
    if len(matches) != 1:
        raise ValueError(f"municipality {municipality_nis} is not exactly one locked acquisition")
    row = matches[0]
    if row.get("status") != "ACQUIRED_ARTIFACT_LOCKED":
        raise ValueError("selected municipality is not ACQUIRED_ARTIFACT_LOCKED")
    artifact = row.get("artifact")
    if not isinstance(artifact, dict):
        raise ValueError("locked acquisition artifact must be an object")
    artifact_id = artifact.get("id")
    artifact_name = artifact.get("name")
    archive_sha256 = artifact.get("archive_sha256")
    raw_semantic_sha256 = row.get("raw_snapshot_semantic_sha256")
    game_semantic_sha256 = row.get("normalized_game_source_semantic_sha256")
    if isinstance(artifact_id, bool) or not isinstance(artifact_id, int) or artifact_id <= 0:
        raise ValueError("invalid locked artifact id")
    if not isinstance(artifact_name, str) or not artifact_name:
        raise ValueError("invalid locked artifact name")
    if not _valid_sha256(archive_sha256):
        raise ValueError("invalid locked artifact archive_sha256")
    if not _valid_sha256(raw_semantic_sha256):
        raise ValueError("invalid locked raw snapshot semantic sha256")
    if not _valid_sha256(game_semantic_sha256):
        raise ValueError("invalid locked normalized game semantic sha256")
    authorization = _require_exact_authorization(row.get("authorization"), DOWNSTREAM_KEY_SET, "locked acquisition authorization")
    for key in DOWNSTREAM_KEYS:
        if authorization[key] is not False:
            raise ValueError(f"evidence lock weakens downstream authorization: {key}")
    return row, artifact_id, artifact_name, archive_sha256, raw_semantic_sha256, game_semantic_sha256


def build_index(artifact_zip: Path, expected_archive_sha256: str, artifact_id: int, artifact_name: str):
    archive = artifact_zip.read_bytes()
    actual_sha = hashlib.sha256(archive).hexdigest()
    if actual_sha != expected_archive_sha256:
        raise ValueError(f"archive sha256 mismatch: {actual_sha}")

    with zipfile.ZipFile(artifact_zip) as zf:
        names = zf.namelist()
        if len(names) != len(set(names)):
            raise ValueError("duplicate ZIP member name")
        for name in names:
            path = Path(name)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError(f"unsafe ZIP member path: {name}")
        if set(names) != set(REQUIRED_MEMBERS) or len(names) != len(REQUIRED_MEMBERS):
            missing = sorted(set(REQUIRED_MEMBERS) - set(names))
            unexpected = sorted(set(names) - set(REQUIRED_MEMBERS))
            raise ValueError(f"locked ZIP member set mismatch: missing={missing} unexpected={unexpected}")
        manifest = _load_json(zf.read(MANIFEST_MEMBER), MANIFEST_MEMBER)
        raw_snapshot = _load_json(zf.read(RAW_MEMBER), RAW_MEMBER)
        game = _load_json(zf.read(GAME_MEMBER), GAME_MEMBER)
        receipt = _load_json(zf.read(RECEIPT_MEMBER), RECEIPT_MEMBER)

    if not isinstance(manifest, dict) or manifest.get("schema") != "grand-bruxelles-municipality-road-source-acquisition-v1":
        raise ValueError("unexpected acquisition manifest schema")
    if not isinstance(receipt, dict) or receipt.get("schema") != "grand-bruxelles-municipality-road-source-receipt-v1":
        raise ValueError("unexpected receipt schema")
    if not isinstance(game, dict) or game.get("format") != "grand-bruxelles-osm-v1":
        raise ValueError("unexpected normalized game format")

    raw_semantic_sha256 = _canonical_json_sha256(raw_snapshot)
    receipt_raw_sha256 = receipt.get("raw_snapshot_sha256")
    if not _valid_sha256(receipt_raw_sha256):
        raise ValueError("invalid receipt raw snapshot semantic sha256")
    if receipt_raw_sha256 != raw_semantic_sha256:
        raise ValueError("raw snapshot semantic sha256 mismatch between payload and receipt")

    game_semantic_sha256 = _canonical_json_sha256(game)
    receipt_game_sha256 = receipt.get("normalized_game_source_sha256")
    if not _valid_sha256(receipt_game_sha256):
        raise ValueError("invalid receipt normalized game semantic sha256")
    if receipt_game_sha256 != game_semantic_sha256:
        raise ValueError("normalized game semantic sha256 mismatch between payload and receipt")

    municipality = manifest.get("municipality")
    if municipality != receipt.get("municipality") or municipality != game.get("municipality"):
        raise ValueError("municipality identity mismatch across locked members")
    if not isinstance(municipality, dict) or not isinstance(municipality.get("osm_relation_id"), int):
        raise ValueError("invalid municipality identity")

    source = manifest.get("source")
    if not isinstance(source, dict) or source != receipt.get("source"):
        raise ValueError("source provenance mismatch")
    if source.get("license") != game.get("license") or source.get("license") != "ODbL-1.0":
        raise ValueError("source license mismatch")

    authorization = _require_exact_authorization(manifest.get("authorization"), MANIFEST_AUTHORIZATION_KEY_SET, "manifest authorization")
    if authorization["source_acquisition_authorized"] is not True:
        raise ValueError("source acquisition is not authorized")
    for key in DOWNSTREAM_KEYS:
        if authorization[key] is not False:
            raise ValueError(f"downstream authorization must stay false: {key}")
    game_authorization = _require_exact_authorization(game.get("authorization"), DOWNSTREAM_KEY_SET, "game authorization")
    receipt_authorization = _require_exact_authorization(receipt.get("authorization"), DOWNSTREAM_KEY_SET, "receipt authorization")
    for key in DOWNSTREAM_KEYS:
        if game_authorization[key] is not False or receipt_authorization[key] is not False:
            raise ValueError(f"locked artifact weakens downstream authorization: {key}")

    roads = game.get("roads")
    expected_roads = receipt.get("road_count")
    expected_points = receipt.get("point_count")
    if not isinstance(roads, list):
        raise ValueError("roads must be a list")
    if isinstance(expected_roads, bool) or not isinstance(expected_roads, int) or expected_roads < 0:
        raise ValueError("invalid receipt road_count")
    if isinstance(expected_points, bool) or not isinstance(expected_points, int) or expected_points < 0:
        raise ValueError("invalid receipt point_count")
    if len(roads) != expected_roads:
        raise ValueError("road_count mismatch")

    seen = set()
    output_roads = []
    point_total = 0
    all_xs: list[float] = []
    all_zs: list[float] = []
    for row in roads:
        if not isinstance(row, dict):
            raise ValueError("road row must be an object")
        osm_id = row.get("osm_id")
        if isinstance(osm_id, bool) or not isinstance(osm_id, int) or osm_id <= 0:
            raise ValueError("invalid OSM road id")
        if osm_id in seen:
            raise ValueError(f"duplicate OSM road id: {osm_id}")
        seen.add(osm_id)
        points = row.get("points")
        if not isinstance(points, list) or len(points) < 2:
            raise ValueError(f"road-{osm_id} has invalid point geometry")
        checked = []
        for i, point in enumerate(points):
            if not isinstance(point, list) or len(point) != 2:
                raise ValueError(f"road-{osm_id} point {i} must be [x,z]")
            checked.append([_finite_number(point[0], f"road-{osm_id} point {i} x"), _finite_number(point[1], f"road-{osm_id} point {i} z")])
        xs = [point[0] for point in checked]
        zs = [point[1] for point in checked]
        all_xs.extend(xs)
        all_zs.extend(zs)
        point_total += len(checked)
        output_roads.append({
            "road_id": f"road-{osm_id}", "osm_id": osm_id, "class": row.get("class"), "name": row.get("name"),
            "point_count": len(checked), "bbox_m": [min(xs), min(zs), max(xs), max(zs)], "points_m": checked,
            "spatial_cell": None, "state": "DISCOVERED", "registration_authorized": False, "render_authorized": False,
            "collision_authorized": False, "runtime_ready": False, "jouable": False,
        })
    if point_total != expected_points:
        raise ValueError("point_count mismatch")

    game_bounds = _checked_bounds(game.get("bounds_m"), "game bounds_m")
    if all_xs:
        geometry_bounds = [round(min(all_xs), 2), round(min(all_zs), 2), round(max(all_xs), 2), round(max(all_zs), 2)]
        if game_bounds != geometry_bounds:
            raise ValueError(f"game bounds_m does not match materialized road geometry: {geometry_bounds}")

    output_roads.sort(key=lambda row: row["osm_id"])
    return {
        "schema": "grand-bruxelles-road-destination-index-v1",
        "municipality": municipality,
        "source": {
            "artifact_id": artifact_id, "artifact_name": artifact_name, "archive_sha256": actual_sha,
            "provider": source["provider"], "endpoint": source["endpoint"], "license": source["license"],
            "osm_base_timestamp": receipt["osm_base_timestamp"], "raw_snapshot_sha256": raw_semantic_sha256,
            "normalized_game_source_sha256": game_semantic_sha256, "origin": game["origin"], "bounds_m": game_bounds,
            "game_frame": manifest["game_frame"],
            "members": {"manifest": MANIFEST_MEMBER, "raw_snapshot": RAW_MEMBER, "game": GAME_MEMBER, "receipt": RECEIPT_MEMBER},
        },
        "accounting": {
            "road_count": expected_roads, "point_count": expected_points, "road_identity_materialized": expected_roads,
            "cell_assignment_materialized": 0, "registered": 0, "rendered": 0, "collision_ready": 0, "runtime_ready": 0, "jouable": 0,
        },
        "roads": output_roads,
    }


def build_index_from_evidence_lock(artifact_zip: Path, evidence_lock: Path, municipality_nis: str):
    locked_row, artifact_id, artifact_name, archive_sha256, raw_semantic_sha256, game_semantic_sha256 = _locked_artifact_selection(evidence_lock, municipality_nis)
    index = build_index(artifact_zip, archive_sha256, artifact_id, artifact_name)
    municipality = index["municipality"]
    if municipality.get("niscode") != locked_row.get("niscode"):
        raise ValueError("artifact municipality NIS does not match evidence lock")
    if municipality.get("id") != locked_row.get("id"):
        raise ValueError("artifact municipality id does not match evidence lock")
    if municipality.get("osm_relation_id") != locked_row.get("osm_relation_id"):
        raise ValueError("artifact OSM relation does not match evidence lock")
    if index["accounting"]["road_count"] != locked_row.get("road_count"):
        raise ValueError("artifact road_count does not match evidence lock")
    if index["accounting"]["point_count"] != locked_row.get("point_count"):
        raise ValueError("artifact point_count does not match evidence lock")
    if index["source"]["osm_base_timestamp"] != locked_row.get("osm_base_timestamp"):
        raise ValueError("artifact OSM base timestamp does not match evidence lock")
    if index["source"]["raw_snapshot_sha256"] != raw_semantic_sha256:
        raise ValueError("artifact raw snapshot semantic sha256 does not match evidence lock")
    if index["source"]["normalized_game_source_sha256"] != game_semantic_sha256:
        raise ValueError("artifact normalized game semantic sha256 does not match evidence lock")
    locked_bounds = _checked_bounds(locked_row.get("bounds_m"), "evidence lock bounds_m")
    if index["source"]["bounds_m"] != locked_bounds:
        raise ValueError("artifact bounds_m does not match evidence lock")
    return index


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-zip", type=Path, required=True)
    parser.add_argument("--evidence-lock", type=Path, required=True)
    parser.add_argument("--municipality-nis", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    index = build_index_from_evidence_lock(args.artifact_zip, args.evidence_lock, args.municipality_nis)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(index, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()