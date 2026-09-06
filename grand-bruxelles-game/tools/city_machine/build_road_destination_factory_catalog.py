#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime
import json
import math
import re
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-road-destination-factory-catalog-v1"
REGISTRY_SCHEMA = "grand-bruxelles-missing-road-source-registry-v1"
EVIDENCE_FORMAT = "grand-bruxelles-missing-road-source-acquisition-evidence-v1"
LOCKED_STATUS = "ACQUIRED_ARTIFACT_LOCKED"
UNRESOLVED_STATUS = "REMOTE_ACQUISITION_UNRESOLVED"
CLOSED_AUTH = {
    "source_registration_authorized",
    "road_cell_mapping_authorized",
    "render_authorized",
    "collision_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
    "jouable_authorized",
}
REGISTRY_AUTH = CLOSED_AUTH | {"source_acquisition_authorized"}
REGISTRY_ROOT_KEYS = {
    "schema",
    "scope",
    "evidence_baseline",
    "source",
    "game_frame",
    "municipalities",
    "authorization",
}
EVIDENCE_ROOT_KEYS = {
    "format",
    "source",
    "game_frame",
    "acquisition_run",
    "accounting",
    "successful_acquisitions",
    "unresolved_acquisitions",
    "authorization",
}
REGISTRY_SOURCE_KEYS = {"provider", "license", "endpoint", "relation_reference"}
EVIDENCE_SOURCE_KEYS = {
    "provider",
    "license",
    "endpoint",
    "query_scope",
    "highway_classes",
    "query_timeout_seconds",
    "transport_timeout_seconds",
}
EXPECTED_EVIDENCE_SOURCE_CONTRACT = {
    "query_scope": "administrative_relation",
    "highway_classes": [
        "motorway",
        "trunk",
        "primary",
        "secondary",
        "tertiary",
        "unclassified",
        "residential",
        "living_street",
        "service",
    ],
    "query_timeout_seconds": 120,
    "transport_timeout_seconds": 150,
}
GAME_FRAME_KEYS = {"origin_lat", "origin_lon", "axes", "units"}
REGISTRY_ROW_KEYS = {"niscode", "id", "name", "osm_relation_id"}
LOCKED_ROW_KEYS = {
    "niscode",
    "id",
    "name",
    "osm_relation_id",
    "status",
    "artifact",
    "osm_base_timestamp",
    "road_count",
    "point_count",
    "bounds_m",
    "raw_snapshot_semantic_sha256",
    "normalized_game_source_semantic_sha256",
    "authorization",
}
UNRESOLVED_ROW_KEYS = {"niscode", "id", "name", "osm_relation_id", "status"}
ARTIFACT_KEYS = {"id", "name", "archive_sha256"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def load_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_object_keys)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: {label}: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: {label} must be an object")
    return value


def _closed_authorization(value: Any, label: str) -> None:
    if not isinstance(value, dict) or set(value) != CLOSED_AUTH:
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: {label} authorization schema drift")
    if any(value[key] is not False for key in CLOSED_AUTH):
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: {label} downstream authorization opened")


def _registry_authorization(value: Any) -> None:
    if not isinstance(value, dict) or set(value) != REGISTRY_AUTH:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: registry authorization schema drift")
    if value["source_acquisition_authorized"] is not True:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: registry source acquisition authorization closed")
    if any(value[key] is not False for key in CLOSED_AUTH):
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: registry downstream authorization opened")


def _validate_provenance_contract(registry: dict[str, Any], evidence: dict[str, Any]) -> None:
    if set(registry) != REGISTRY_ROOT_KEYS:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: registry root schema drift")
    if set(evidence) != EVIDENCE_ROOT_KEYS:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: evidence root schema drift")
    if registry.get("schema") != REGISTRY_SCHEMA:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: invalid registry schema")
    if evidence.get("format") != EVIDENCE_FORMAT:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: invalid evidence format")

    registry_source = registry.get("source")
    evidence_source = evidence.get("source")
    if not isinstance(registry_source, dict) or set(registry_source) != REGISTRY_SOURCE_KEYS:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: registry source schema drift")
    if not isinstance(evidence_source, dict) or set(evidence_source) != EVIDENCE_SOURCE_KEYS:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: evidence source schema drift")
    for key in ("provider", "license", "endpoint"):
        if registry_source.get(key) != evidence_source.get(key):
            raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: source provenance drift for {key}")
    for key, expected in EXPECTED_EVIDENCE_SOURCE_CONTRACT.items():
        if evidence_source.get(key) != expected:
            raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: evidence source contract drift for {key}")

    registry_frame = registry.get("game_frame")
    evidence_frame = evidence.get("game_frame")
    if not isinstance(registry_frame, dict) or set(registry_frame) != GAME_FRAME_KEYS:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: registry game frame schema drift")
    if not isinstance(evidence_frame, dict) or set(evidence_frame) != GAME_FRAME_KEYS:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: evidence game frame schema drift")
    if registry_frame != evidence_frame:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: game frame drift")


def _validate_artifact(value: Any, nis: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != ARTIFACT_KEYS:
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: locked artifact schema drift for {nis}")
    artifact_id = value.get("id")
    name = value.get("name")
    archive_sha256 = value.get("archive_sha256")
    if isinstance(artifact_id, bool) or not isinstance(artifact_id, int) or artifact_id <= 0:
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked artifact for {nis}")
    if not isinstance(name, str) or not name:
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked artifact for {nis}")
    if not isinstance(archive_sha256, str) or SHA256_RE.fullmatch(archive_sha256) is None:
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked artifact for {nis}")
    return value


def _validate_locked_source_evidence(row: dict[str, Any], nis: str) -> None:
    road_count = row.get("road_count")
    point_count = row.get("point_count")
    if (
        isinstance(road_count, bool)
        or not isinstance(road_count, int)
        or road_count <= 0
        or isinstance(point_count, bool)
        or not isinstance(point_count, int)
        or point_count <= 0
    ):
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked source evidence for {nis}")

    bounds = row.get("bounds_m")
    if not isinstance(bounds, list) or len(bounds) != 4:
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked source evidence for {nis}")
    values: list[float] = []
    for value in bounds:
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked source evidence for {nis}")
        values.append(float(value))
    min_x, min_z, max_x, max_z = values
    if min_x >= max_x or min_z >= max_z:
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked source evidence for {nis}")

    timestamp = row.get("osm_base_timestamp")
    if not isinstance(timestamp, str) or not timestamp.endswith("Z"):
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked source evidence for {nis}")
    try:
        parsed = datetime.fromisoformat(timestamp[:-1] + "+00:00")
    except ValueError as exc:
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked source evidence for {nis}") from exc
    if parsed.utcoffset() is None or parsed.utcoffset().total_seconds() != 0:
        raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked source evidence for {nis}")

    for key in ("raw_snapshot_semantic_sha256", "normalized_game_source_semantic_sha256"):
        digest = row.get(key)
        if not isinstance(digest, str) or SHA256_RE.fullmatch(digest) is None:
            raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: invalid locked source evidence for {nis}")


def build_catalog(registry: dict[str, Any], evidence: dict[str, Any]) -> dict[str, Any]:
    _validate_provenance_contract(registry, evidence)

    municipalities = registry.get("municipalities")
    if not isinstance(municipalities, list) or not municipalities:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: invalid registry municipalities")
    _registry_authorization(registry.get("authorization"))

    successful = evidence.get("successful_acquisitions")
    unresolved = evidence.get("unresolved_acquisitions")
    if not isinstance(successful, list) or not isinstance(unresolved, list):
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: invalid evidence partitions")
    _closed_authorization(evidence.get("authorization"), "evidence")

    locked_by_nis: dict[str, dict[str, Any]] = {}
    unresolved_by_nis: dict[str, dict[str, Any]] = {}
    for row in successful:
        if not isinstance(row, dict) or set(row) != LOCKED_ROW_KEYS:
            raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: locked acquisition schema drift")
        if row.get("status") != LOCKED_STATUS:
            raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: invalid locked acquisition row")
        nis = row.get("niscode")
        if not isinstance(nis, str) or nis in locked_by_nis:
            raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: duplicate/invalid locked NIS")
        _closed_authorization(row.get("authorization"), f"locked {nis}")
        _validate_artifact(row.get("artifact"), nis)
        _validate_locked_source_evidence(row, nis)
        locked_by_nis[nis] = row
    for row in unresolved:
        if not isinstance(row, dict) or set(row) != UNRESOLVED_ROW_KEYS:
            raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: unresolved acquisition schema drift")
        if row.get("status") != UNRESOLVED_STATUS:
            raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: invalid unresolved acquisition row")
        nis = row.get("niscode")
        if not isinstance(nis, str) or nis in unresolved_by_nis:
            raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: duplicate/invalid unresolved NIS")
        unresolved_by_nis[nis] = row
    if set(locked_by_nis) & set(unresolved_by_nis):
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: acquisition partitions overlap")

    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for registry_row in municipalities:
        if not isinstance(registry_row, dict) or set(registry_row) != REGISTRY_ROW_KEYS:
            raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: registry municipality schema drift")
        nis = registry_row.get("niscode")
        if not isinstance(nis, str) or nis in seen:
            raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: duplicate/invalid registry NIS")
        seen.add(nis)
        source_row = locked_by_nis.get(nis) or unresolved_by_nis.get(nis)
        if source_row is None:
            raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: missing evidence for {nis}")
        for key in ("id", "name", "osm_relation_id"):
            if source_row.get(key) != registry_row.get(key):
                raise SystemExit(f"DESTINATION_FACTORY_CATALOG_FAIL: identity drift for {nis}/{key}")
        locked = nis in locked_by_nis
        artifact = _validate_artifact(source_row.get("artifact"), nis) if locked else None
        rows.append({
            "niscode": nis,
            "id": registry_row["id"],
            "osm_relation_id": registry_row["osm_relation_id"],
            "source_status": LOCKED_STATUS if locked else UNRESOLVED_STATUS,
            "artifact_name": artifact["name"] if locked else None,
            "source_file": None,
            "road_identity_status": "NOT_MATERIALIZED_FROM_SOURCE_ARTIFACT" if locked else "SOURCE_UNRESOLVED",
            "cell_status": "NOT_ASSIGNED",
            "registration_authorized": False,
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_ready": False,
            "jouable": False,
        })

    partition = set(locked_by_nis) | set(unresolved_by_nis)
    if seen != partition:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: registry/evidence accounting drift")
    accounting = evidence.get("accounting")
    expected = len(rows)
    if not isinstance(accounting, dict) or any(isinstance(accounting.get(k), bool) or not isinstance(accounting.get(k), int) for k in ("expected_municipalities", "successful_acquisitions", "unresolved_acquisitions")):
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: invalid evidence accounting")
    if accounting != {"expected_municipalities": expected, "successful_acquisitions": len(locked_by_nis), "unresolved_acquisitions": len(unresolved_by_nis)}:
        raise SystemExit("DESTINATION_FACTORY_CATALOG_FAIL: evidence accounting mismatch")

    return {
        "schema": SCHEMA,
        "derivation": {
            "source_registry": "data/source_plans/brussels_missing_road_source_registry.json",
            "acquisition_evidence_lock": "data/source_plans/brussels_missing_road_source_acquisition_evidence.lock.json",
            "rule": "municipality readiness only; road identities/cells require materialized locked source artifacts",
        },
        "accounting": {
            "expected_municipalities": expected,
            "acquired_artifact_locked": len(locked_by_nis),
            "remote_acquisition_unresolved": len(unresolved_by_nis),
            "road_identity_materialized": 0,
            "cell_assignment_materialized": 0,
        },
        "municipalities": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    catalog = build_catalog(load_object(args.registry, "registry"), load_object(args.evidence, "evidence"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"DESTINATION_FACTORY_CATALOG_GREEN: municipalities={catalog['accounting']['expected_municipalities']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
