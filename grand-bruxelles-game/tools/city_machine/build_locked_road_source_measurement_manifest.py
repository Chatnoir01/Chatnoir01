#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-locked-road-source-measurements-v1"
EVIDENCE_FORMAT = "grand-bruxelles-missing-road-source-acquisition-evidence-v1"
EXPECTED_EVIDENCE_GIT_BLOB_SHA1 = "785688868931d48845f1df47837feff7861399d7"
EXPECTED_SOURCE = {
    "provider": "OpenStreetMap contributors via Overpass API",
    "license": "ODbL-1.0",
    "endpoint": "https://overpass-api.de/api/interpreter",
}
EXPECTED_GAME_FRAME = {"origin_lat": 50.8419, "origin_lon": 4.348, "axes": "X=east, Y=up, Z=south", "units": "metres"}
EXPECTED_RUN = {
    "workflow": "Grand Bruxelles Missing Road Source Batch",
    "run_id": 33343196025,
    "source_pr": 1675,
    "source_head_sha": "c9606e28eae99ef9dca77be53bb4e7a83cb94e7f",
}
EXPECTED_ACCOUNTING = {
    "expected_municipalities": 16,
    "successful_acquisitions": 7,
    "unresolved_acquisitions": 9,
}
LOCKED_STATUS = "ACQUIRED_ARTIFACT_LOCKED"
UNRESOLVED_STATUS = "REMOTE_ACQUISITION_UNRESOLVED"


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _git_blob_sha1(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()


def _positive_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def _nonempty_str(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _valid_niscode(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 5 and value.startswith("21") and value.isascii() and value.isdigit()


def _sha256_hex(value: Any) -> bool:
    if not isinstance(value, str) or len(value) != 64:
        return False
    return all(char in "0123456789abcdef" for char in value)


def _valid_bounds_m(value: Any) -> bool:
    if not isinstance(value, list) or len(value) != 4:
        return False
    if any(isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(item) for item in value):
        return False
    min_x, min_z, max_x, max_z = value
    return min_x < max_x and min_z < max_z


def _register_identity(row: dict[str, Any], seen_ids: set[str], seen_relations: set[int]) -> bool:
    municipality_id = row.get("id")
    relation_id = row.get("osm_relation_id")
    if not _nonempty_str(municipality_id) or not _positive_int(relation_id):
        return False
    if municipality_id in seen_ids or relation_id in seen_relations:
        raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: municipality identity collision")
    seen_ids.add(municipality_id)
    seen_relations.add(relation_id)
    return True


def build(evidence_path: Path) -> dict[str, Any]:
    raw = evidence_path.read_bytes()
    if _git_blob_sha1(raw) != EXPECTED_EVIDENCE_GIT_BLOB_SHA1:
        raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: evidence Git blob drift")
    evidence = json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_keys)
    if evidence.get("format") != EVIDENCE_FORMAT:
        raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: evidence format drift")
    source = evidence.get("source")
    if not isinstance(source, dict) or any(source.get(k) != v for k, v in EXPECTED_SOURCE.items()):
        raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: source provenance drift")
    if evidence.get("game_frame") != EXPECTED_GAME_FRAME:
        raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: game frame drift")
    if evidence.get("acquisition_run") != EXPECTED_RUN:
        raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: acquisition run drift")
    successful = evidence.get("successful_acquisitions")
    unresolved = evidence.get("unresolved_acquisitions")
    accounting = evidence.get("accounting")
    if not isinstance(successful, list) or not isinstance(unresolved, list) or not isinstance(accounting, dict):
        raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: acquisition evidence schema drift")
    if accounting != EXPECTED_ACCOUNTING:
        raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: regional acquisition accounting drift")
    if len(successful) != EXPECTED_ACCOUNTING["successful_acquisitions"] or len(unresolved) != EXPECTED_ACCOUNTING["unresolved_acquisitions"]:
        raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: acquisition list accounting drift")
    if len(successful) + len(unresolved) != EXPECTED_ACCOUNTING["expected_municipalities"]:
        raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: regional municipality accounting drift")

    unresolved_niscodes: set[str] = set()
    seen_ids: set[str] = set()
    seen_relations: set[int] = set()
    for row in unresolved:
        if not isinstance(row, dict) or row.get("status") != UNRESOLVED_STATUS:
            raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: unresolved row drift")
        nis = row.get("niscode")
        if (
            not _valid_niscode(nis)
            or nis in unresolved_niscodes
            or not _nonempty_str(row.get("name"))
            or not _register_identity(row, seen_ids, seen_relations)
        ):
            raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: unresolved identity drift")
        unresolved_niscodes.add(nis)

    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in successful:
        if not isinstance(row, dict) or row.get("status") != LOCKED_STATUS:
            raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: locked row drift")
        nis = row.get("niscode")
        artifact = row.get("artifact")
        if not _valid_niscode(nis) or nis in seen or nis in unresolved_niscodes or not isinstance(artifact, dict):
            raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: locked identity drift")
        if (
            not _nonempty_str(row.get("name"))
            or not _register_identity(row, seen_ids, seen_relations)
            or not _nonempty_str(artifact.get("name"))
            or not _sha256_hex(artifact.get("archive_sha256"))
        ):
            raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: locked metadata drift")
        if not _positive_int(row.get("road_count")) or not _positive_int(row.get("point_count")) or not _valid_bounds_m(row.get("bounds_m")):
            raise SystemExit("LOCKED_ROAD_SOURCE_MEASUREMENTS_FAIL: measurement geometry drift")
        seen.add(nis)
        rows.append({
            "niscode": nis,
            "id": row["id"],
            "name": row["name"],
            "osm_relation_id": row["osm_relation_id"],
            "artifact_name": artifact["name"],
            "archive_sha256": artifact["archive_sha256"],
            "road_count": row["road_count"],
            "point_count": row["point_count"],
            "bounds_m": row["bounds_m"],
            "source_file": None,
            "spatial_cell": None,
            "road_identity_status": "NOT_MATERIALIZED_FROM_SOURCE_ARTIFACT",
            "cell_status": "NOT_ASSIGNED",
            "registration_authorized": False,
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_ready": False,
            "jouable": False,
        })
    rows.sort(key=lambda item: item["niscode"])
    return {
        "schema": SCHEMA,
        "source_evidence_git_blob_sha1": EXPECTED_EVIDENCE_GIT_BLOB_SHA1,
        "source": {
            **EXPECTED_SOURCE,
            "game_frame": EXPECTED_GAME_FRAME,
            "acquisition_run": EXPECTED_RUN,
        },
        "accounting": {
            "expected_municipalities": EXPECTED_ACCOUNTING["expected_municipalities"],
            "locked_municipalities": len(rows),
            "unresolved_municipalities": len(unresolved),
            "road_identity_materialized": 0,
            "cell_assignment_materialized": 0,
        },
        "municipalities": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    payload = build(args.evidence)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"LOCKED_ROAD_SOURCE_MEASUREMENTS_GREEN: municipalities={len(payload['municipalities'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
