from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path, PurePosixPath
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_SCHEMA = "grand-bruxelles-spatial-crosswalk-precondition-v1"
EXPECTED_MEASUREMENTS_SCHEMA = "grand-bruxelles-locked-road-source-measurements-v1"
EXPECTED_MEASUREMENTS_PATH = "data/source_plans/brussels_locked_road_source_measurements.lock.json"
EXPECTED_EVIDENCE_GIT_BLOB_SHA1 = "785688868931d48845f1df47837feff7861399d7"
EXPECTED_SOURCE_FRAME = {
    "origin_lat": 50.8419,
    "origin_lon": 4.348,
    "axes": "X=east, Y=up, Z=south",
    "units": "metres",
}
EXPECTED_SOURCE_PROVIDER = "OpenStreetMap contributors via Overpass API"
EXPECTED_SOURCE_LICENSE = "ODbL-1.0"
EXPECTED_SOURCE_ENDPOINT = "https://overpass-api.de/api/interpreter"
EXPECTED_ACQUISITION_RUN = {
    "workflow": "Grand Bruxelles Missing Road Source Batch",
    "run_id": 33343196025,
    "source_pr": 1675,
    "source_head_sha": "c9606e28eae99ef9dca77be53bb4e7a83cb94e7f",
}
EXPECTED_MEASUREMENT_TOP_LEVEL_KEYS = {
    "schema",
    "source_evidence_git_blob_sha1",
    "source",
    "accounting",
    "municipalities",
}
EXPECTED_MEASUREMENT_SOURCE_KEYS = {
    "provider",
    "license",
    "endpoint",
    "game_frame",
    "acquisition_run",
}
EXPECTED_ACQUISITION_RUN_KEYS = {"workflow", "run_id", "source_pr", "source_head_sha"}
EXPECTED_ACCOUNTING_KEYS = {
    "expected_municipalities",
    "locked_municipalities",
    "unresolved_municipalities",
    "road_identity_materialized",
    "cell_assignment_materialized",
}
EXPECTED_MUNICIPALITY_KEYS = {
    "niscode",
    "id",
    "name",
    "osm_relation_id",
    "artifact_name",
    "archive_sha256",
    "road_count",
    "point_count",
    "bounds_m",
    "source_file",
    "spatial_cell",
    "road_identity_status",
    "cell_status",
    "registration_authorized",
    "render_authorized",
    "collision_authorized",
    "runtime_ready",
    "jouable",
}
EXPECTED_REQUIRED_PROVENANCE = [
    "target_grid_contract",
    "target_crs",
    "transform_source",
    "transform_revision",
    "transform_license",
    "transform_sha256",
]
EXPECTED_AUTHORIZATION_KEYS = {
    "road_identity_materialized",
    "cell_assignment_materialized",
    "registration_authorized",
    "render_authorized",
    "collision_authorized",
    "runtime_ready",
    "jouable",
}
LOWER_HEX_40 = re.compile(r"^[0-9a-f]{40}$")
LOWER_HEX_64 = re.compile(r"^[0-9a-f]{64}$")
EPSG = re.compile(r"^EPSG:[1-9][0-9]*$")


def _git_blob_sha1(raw: bytes) -> str:
    return hashlib.sha1(f"blob {len(raw)}\0".encode("ascii") + raw).hexdigest()


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _load_json_no_duplicate_keys(raw: bytes, label: str) -> Any:
    try:
        text = raw.decode("utf-8")
        return json.loads(text, object_pairs_hook=_reject_duplicate_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is not valid UTF-8 JSON") from exc


def _require_nonempty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        raise ValueError(f"{label} must be a non-empty trimmed string")
    return value


def _resolve_repo_path(repo_root: Path, raw_path: Any, label: str) -> Path:
    path_text = _require_nonempty_string(raw_path, label)
    posix = PurePosixPath(path_text)
    if posix.is_absolute() or ".." in posix.parts or "." in posix.parts:
        raise ValueError(f"{label} must be a repository-relative canonical path")
    candidate = (repo_root / Path(*posix.parts)).resolve()
    root = repo_root.resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"{label} escapes repository root") from exc
    return candidate


def _require_exact_zero_integer(value: Any, label: str) -> None:
    if type(value) is not int or value != 0:
        raise ValueError(f"{label} must be integer zero")


def _require_exact_integer(value: Any, expected: int, label: str) -> None:
    if type(value) is not int or value != expected:
        raise ValueError(f"{label} must be integer {expected}")


def _validate_closed_authorization(authorization: Any) -> None:
    if not isinstance(authorization, dict) or set(authorization) != EXPECTED_AUTHORIZATION_KEYS:
        raise ValueError("authorization schema drift")
    _require_exact_zero_integer(authorization["road_identity_materialized"], "road_identity_materialized")
    _require_exact_zero_integer(authorization["cell_assignment_materialized"], "cell_assignment_materialized")
    for key in ("registration_authorized", "render_authorized", "collision_authorized", "runtime_ready", "jouable"):
        if authorization[key] is not False:
            raise ValueError(f"{key} must remain false at crosswalk-precondition stage")


def _validate_measurement_schema_and_provenance(measurements: dict[str, Any]) -> None:
    if set(measurements) != EXPECTED_MEASUREMENT_TOP_LEVEL_KEYS:
        raise ValueError("source measurements top-level schema drift")
    if measurements["schema"] != EXPECTED_MEASUREMENTS_SCHEMA:
        raise ValueError("source measurements schema drift")
    if measurements["source_evidence_git_blob_sha1"] != EXPECTED_EVIDENCE_GIT_BLOB_SHA1:
        raise ValueError("measurement evidence pin mismatch")

    source = measurements["source"]
    if not isinstance(source, dict) or set(source) != EXPECTED_MEASUREMENT_SOURCE_KEYS:
        raise ValueError("source measurements source schema drift")
    if source["provider"] != EXPECTED_SOURCE_PROVIDER:
        raise ValueError("measurement source provider drift")
    if source["license"] != EXPECTED_SOURCE_LICENSE:
        raise ValueError("measurement source license drift")
    if source["endpoint"] != EXPECTED_SOURCE_ENDPOINT:
        raise ValueError("measurement source endpoint drift")
    if source["game_frame"] != EXPECTED_SOURCE_FRAME:
        raise ValueError("measurement source frame mismatch")

    acquisition = source["acquisition_run"]
    if not isinstance(acquisition, dict) or set(acquisition) != EXPECTED_ACQUISITION_RUN_KEYS:
        raise ValueError("source measurements acquisition-run schema drift")
    if acquisition != EXPECTED_ACQUISITION_RUN:
        raise ValueError("measurement acquisition-run provenance drift")

    accounting = measurements["accounting"]
    if not isinstance(accounting, dict) or set(accounting) != EXPECTED_ACCOUNTING_KEYS:
        raise ValueError("source measurements accounting schema drift")
    _require_exact_integer(accounting["expected_municipalities"], 16, "measurement accounting expected_municipalities")
    _require_exact_integer(accounting["locked_municipalities"], 7, "measurement accounting locked_municipalities")
    _require_exact_integer(accounting["unresolved_municipalities"], 9, "measurement accounting unresolved_municipalities")
    _require_exact_zero_integer(accounting["road_identity_materialized"], "measurement accounting road_identity_materialized")
    _require_exact_zero_integer(accounting["cell_assignment_materialized"], "measurement accounting cell_assignment_materialized")


def _validate_measurement_rows_closed(measurements: dict[str, Any]) -> None:
    municipalities = measurements.get("municipalities")
    if not isinstance(municipalities, list) or not municipalities:
        raise ValueError("measurement municipalities must be a non-empty list")

    locked_count = measurements["accounting"]["locked_municipalities"]
    if len(municipalities) != locked_count:
        raise ValueError("measurement municipality row count must equal locked_municipalities")

    seen_niscodes: set[str] = set()
    seen_ids: set[str] = set()
    seen_relations: set[int] = set()

    for index, row in enumerate(municipalities):
        if not isinstance(row, dict):
            raise ValueError(f"measurement municipality[{index}] must be an object")
        if set(row) != EXPECTED_MUNICIPALITY_KEYS:
            raise ValueError(f"measurement municipality[{index}] schema drift")

        niscode = _require_nonempty_string(row["niscode"], f"measurement municipality[{index}].niscode")
        municipality_id = _require_nonempty_string(row["id"], f"measurement municipality[{index}].id")
        relation_id = row["osm_relation_id"]
        if type(relation_id) is not int or relation_id <= 0:
            raise ValueError(f"measurement municipality[{index}].osm_relation_id must be a positive integer")
        if niscode in seen_niscodes:
            raise ValueError(f"duplicate niscode in measurement municipalities: {niscode}")
        if municipality_id in seen_ids:
            raise ValueError(f"duplicate municipality id in measurement municipalities: {municipality_id}")
        if relation_id in seen_relations:
            raise ValueError(f"duplicate osm_relation_id in measurement municipalities: {relation_id}")
        seen_niscodes.add(niscode)
        seen_ids.add(municipality_id)
        seen_relations.add(relation_id)

        if row["source_file"] is not None:
            raise ValueError(f"measurement municipality[{index}].source_file must remain null")
        if row["road_identity_status"] != "NOT_MATERIALIZED_FROM_SOURCE_ARTIFACT":
            raise ValueError(
                f"measurement municipality[{index}].road_identity_status must remain NOT_MATERIALIZED_FROM_SOURCE_ARTIFACT"
            )
        if row["spatial_cell"] is not None:
            raise ValueError(f"measurement municipality[{index}].spatial_cell must remain null")
        if row["cell_status"] != "NOT_ASSIGNED":
            raise ValueError(f"measurement municipality[{index}].cell_status must remain NOT_ASSIGNED")
        for key in ("registration_authorized", "render_authorized", "collision_authorized", "runtime_ready", "jouable"):
            if row[key] is not False:
                raise ValueError(f"measurement municipality[{index}].{key} must remain false")


def _validate_target_grid_contract(contract: Any, repo_root: Path) -> None:
    if not isinstance(contract, dict) or set(contract) != {"path", "git_blob_sha1"}:
        raise ValueError("target_grid_contract must contain only path and git_blob_sha1")
    path = _resolve_repo_path(repo_root, contract["path"], "target_grid_contract.path")
    blob = contract["git_blob_sha1"]
    if not isinstance(blob, str) or LOWER_HEX_40.fullmatch(blob) is None:
        raise ValueError("target_grid_contract.git_blob_sha1 must be lowercase Git SHA-1")
    if not path.is_file():
        raise ValueError("target grid contract path does not exist")
    if _git_blob_sha1(path.read_bytes()) != blob:
        raise ValueError("target grid contract Git blob mismatch")


def validate_crosswalk_precondition(payload: Any, measurements_raw: bytes, *, repo_root: Path = ROOT) -> None:
    if not isinstance(payload, dict) or set(payload) != {"schema", "source_measurement_manifest", "crosswalk", "authorization"}:
        raise ValueError("spatial crosswalk precondition schema drift")
    if payload["schema"] != EXPECTED_SCHEMA:
        raise ValueError("unexpected spatial crosswalk schema")

    source = payload["source_measurement_manifest"]
    if not isinstance(source, dict) or set(source) != {"path", "git_blob_sha1", "source_evidence_git_blob_sha1", "source_frame"}:
        raise ValueError("source measurement manifest contract drift")
    if source["path"] != EXPECTED_MEASUREMENTS_PATH:
        raise ValueError("source measurement manifest path drift")
    if source["git_blob_sha1"] != _git_blob_sha1(measurements_raw):
        raise ValueError("source measurement manifest Git blob mismatch")
    if source["source_evidence_git_blob_sha1"] != EXPECTED_EVIDENCE_GIT_BLOB_SHA1:
        raise ValueError("source evidence Git blob drift")
    if source["source_frame"] != EXPECTED_SOURCE_FRAME:
        raise ValueError("source game-frame contract drift")

    measurements = _load_json_no_duplicate_keys(measurements_raw, "source measurements")
    if not isinstance(measurements, dict):
        raise ValueError("source measurements must be a JSON object")
    _validate_measurement_schema_and_provenance(measurements)
    _validate_measurement_rows_closed(measurements)

    crosswalk = payload["crosswalk"]
    if not isinstance(crosswalk, dict) or set(crosswalk) != {"status", "authorized", *EXPECTED_REQUIRED_PROVENANCE, "required_before_authorization"}:
        raise ValueError("crosswalk schema drift")
    if crosswalk["required_before_authorization"] != EXPECTED_REQUIRED_PROVENANCE:
        raise ValueError("crosswalk provenance requirements drift")
    _validate_closed_authorization(payload["authorization"])

    if crosswalk["authorized"] is False:
        if crosswalk["status"] != "UNRESOLVED_PROVENANCE":
            raise ValueError("unauthorized crosswalk must remain UNRESOLVED_PROVENANCE")
        if any(crosswalk[key] is not None for key in EXPECTED_REQUIRED_PROVENANCE):
            raise ValueError("unresolved crosswalk must not carry guessed provenance")
        return
    if crosswalk["authorized"] is not True or crosswalk["status"] != "PROVENANCE_LOCKED":
        raise ValueError("authorized crosswalk requires PROVENANCE_LOCKED status")

    _validate_target_grid_contract(crosswalk["target_grid_contract"], repo_root)
    target_crs = _require_nonempty_string(crosswalk["target_crs"], "target_crs")
    if EPSG.fullmatch(target_crs) is None:
        raise ValueError("target_crs must be an explicit EPSG identifier")
    _require_nonempty_string(crosswalk["transform_source"], "transform_source")
    _require_nonempty_string(crosswalk["transform_revision"], "transform_revision")
    _require_nonempty_string(crosswalk["transform_license"], "transform_license")
    transform_sha256 = crosswalk["transform_sha256"]
    if not isinstance(transform_sha256, str) or LOWER_HEX_64.fullmatch(transform_sha256) is None:
        raise ValueError("transform_sha256 must be lowercase SHA-256")


def main() -> int:
    precondition = ROOT / "data/source_plans/brussels_spatial_crosswalk_precondition.lock.json"
    measurements = ROOT / EXPECTED_MEASUREMENTS_PATH
    payload = _load_json_no_duplicate_keys(precondition.read_bytes(), "spatial crosswalk precondition")
    validate_crosswalk_precondition(payload, measurements.read_bytes(), repo_root=ROOT)
    print("spatial crosswalk precondition: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
