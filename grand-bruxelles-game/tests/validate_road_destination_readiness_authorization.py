#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
import math
import re
from pathlib import Path
from typing import Any

EXPECTED_SCHEMA = "grand-bruxelles-road-destination-readiness-catalog-v1"
EXPECTED_MIGRATION_STATE = "CORRECTED_FRAME_REGISTERED_NOT_RENDERED"
EXPECTED_STATUS = "SOURCE_BACKED_REGISTERED_NOT_RENDERED"
EXPECTED_CELL_CRS = "EPSG:31370"
CELL_ID_RE = re.compile(r"^bxl-e([0-9]+)-n([0-9]+)-s([1-9][0-9]*)$")
ROOT_KEYS = frozenset(
    {
        "authorization",
        "corrected_frame_candidate_semantic_sha256",
        "corrected_frame_source_sha256",
        "destination_count",
        "destinations",
        "mapped_cell_count",
        "migration_state",
        "registered_cell_index_semantic_sha256",
        "road_cell_crosswalk_semantic_sha256",
        "road_runtime_catalog_sha256",
        "schema",
        "semantic_sha256",
        "source_document_count",
        "status",
    }
)
TOP_LEVEL_FLAGS = (
    "collision_authorized",
    "jouable_authorized",
    "render_authorized",
    "road_cell_mapping_authorized",
    "runtime_directory_scan_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
)
ROW_FLAGS = (
    "collision_authorized",
    "jouable_authorized",
    "render_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
)
ROW_KEYS = frozenset(
    {
        "cell_bbox",
        "cell_crs",
        "cell_id",
        "cell_manifest_path",
        "cell_manifest_sha256",
        "collision_authorized",
        "destination_id",
        "grid_cell_id",
        "jouable_authorized",
        "municipalities",
        "municipality_niscodes",
        "readiness",
        "render_authorized",
        "road_class",
        "road_name",
        "road_osm_id",
        "road_width_m",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
        "source_license",
        "source_local_bbox",
        "source_local_point_count",
        "source_path",
        "source_points_sha256",
        "source_provider",
        "source_sha256",
    }
)
EXPECTED_READINESS = "REGISTERED_NOT_RENDERED"


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key: {key}")
        out[key] = value
    return out


def _finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite JSON number: {value}")
    return parsed


def _load(path: Path) -> dict[str, Any]:
    parsed = json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=_strict_object,
        parse_float=_finite_float,
        parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"non-finite JSON number: {value}")),
    )
    if not isinstance(parsed, dict):
        raise ValueError("catalog root must be an object")
    return parsed


def _require_false(value: Any, label: str) -> None:
    if value is not False:
        raise ValueError(f"{label} must be boolean false before promotion")


def _require_exact_keys(value: dict[str, Any], expected: frozenset[str], label: str) -> None:
    actual = frozenset(value)
    if actual == expected:
        return
    missing = sorted(expected - actual)
    unknown = sorted(actual - expected)
    raise ValueError(f"{label} schema mismatch: missing={missing} unknown={unknown}")


def _require_exact_count(value: Any, actual: int, label: str) -> None:
    if type(value) is not int:
        raise ValueError(f"{label} must be an integer")
    if value != actual:
        raise ValueError(f"{label}={value} does not match derived count={actual}")


def _require_nonempty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a non-empty string")
    return value


def _require_finite_number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{label} must be a finite number")
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"{label} must be a finite number")
    return parsed


def _validate_cell_identity(row: dict[str, Any], index: int) -> None:
    label = f"destination row {index}"
    cell_id = _require_nonempty_string(row["cell_id"], f"{label}.cell_id")
    match = CELL_ID_RE.fullmatch(cell_id)
    if match is None:
        raise ValueError(f"{label}.cell_id must use canonical bxl-e<N>-n<N>-s<S> identity")

    easting = int(match.group(1))
    northing = int(match.group(2))
    size = int(match.group(3))
    expected_grid = f"E{easting}_N{northing}"
    if row["grid_cell_id"] != expected_grid:
        raise ValueError(f"{label}.grid_cell_id must equal {expected_grid}")

    expected_manifest = f"data/cell_manifests/{cell_id}.json"
    if row["cell_manifest_path"] != expected_manifest:
        raise ValueError(f"{label}.cell_manifest_path must equal {expected_manifest}")

    if row["cell_crs"] != EXPECTED_CELL_CRS:
        raise ValueError(f"{label}.cell_crs must remain {EXPECTED_CELL_CRS}")

    bbox = row["cell_bbox"]
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise ValueError(f"{label}.cell_bbox must contain four finite coordinates")
    actual_bbox = [_require_finite_number(value, f"{label}.cell_bbox[{offset}]") for offset, value in enumerate(bbox)]
    expected_bbox = [float(easting), float(northing), float(easting + size), float(northing + size)]
    if actual_bbox != expected_bbox:
        raise ValueError(f"{label}.cell_bbox={actual_bbox} does not match cell identity {expected_bbox}")


def validate(catalog: dict[str, Any]) -> int:
    _require_exact_keys(catalog, ROOT_KEYS, "catalog root")
    if catalog.get("schema") != EXPECTED_SCHEMA:
        raise ValueError("unexpected catalog schema")
    if catalog.get("migration_state") != EXPECTED_MIGRATION_STATE:
        raise ValueError(f"catalog migration_state must remain {EXPECTED_MIGRATION_STATE}")
    if catalog.get("status") != EXPECTED_STATUS:
        raise ValueError(f"catalog status must remain {EXPECTED_STATUS}")
    authorization = catalog.get("authorization")
    if not isinstance(authorization, dict):
        raise ValueError("catalog authorization must be an object")
    _require_exact_keys(authorization, frozenset(TOP_LEVEL_FLAGS), "catalog authorization")
    for flag in TOP_LEVEL_FLAGS:
        _require_false(authorization[flag], f"authorization.{flag}")

    rows = catalog.get("destinations")
    if not isinstance(rows, list) or not rows:
        raise ValueError("catalog destinations missing")
    _require_exact_count(catalog.get("destination_count"), len(rows), "destination_count")

    mapped_cells: set[str] = set()
    source_documents: set[str] = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ValueError(f"destination row {index} must be an object")
        _require_exact_keys(row, ROW_KEYS, f"destination row {index}")
        if row.get("readiness") != EXPECTED_READINESS:
            raise ValueError(f"destination row {index} readiness must remain {EXPECTED_READINESS}")
        for flag in ROW_FLAGS:
            _require_false(row[flag], f"destination row {index}.{flag}")
        _validate_cell_identity(row, index)
        mapped_cells.add(_require_nonempty_string(row["cell_id"], f"destination row {index}.cell_id"))
        source_documents.add(_require_nonempty_string(row["source_path"], f"destination row {index}.source_path"))

    _require_exact_count(catalog.get("mapped_cell_count"), len(mapped_cells), "mapped_cell_count")
    _require_exact_count(catalog.get("source_document_count"), len(source_documents), "source_document_count")
    return len(rows)


def self_test(catalog: dict[str, Any]) -> None:
    validate(catalog)
    cases: list[tuple[str, dict[str, Any]]] = []

    top_true = copy.deepcopy(catalog)
    top_true["authorization"]["jouable_authorized"] = True
    cases.append(("top-level true", top_true))

    row_true = copy.deepcopy(catalog)
    row_true["destinations"][0]["safe_spawn_authorized"] = True
    cases.append(("row true", row_true))

    string_false = copy.deepcopy(catalog)
    string_false["destinations"][0]["render_authorized"] = "false"
    cases.append(("string false", string_false))

    readiness_promoted = copy.deepcopy(catalog)
    readiness_promoted["destinations"][0]["readiness"] = "PLAYABLE"
    cases.append(("readiness promotion", readiness_promoted))

    migration_promoted = copy.deepcopy(catalog)
    migration_promoted["migration_state"] = "JOUABLE"
    cases.append(("migration state promotion", migration_promoted))

    status_promoted = copy.deepcopy(catalog)
    status_promoted["status"] = "JOUABLE"
    cases.append(("status promotion", status_promoted))

    shadow_root_authorization = copy.deepcopy(catalog)
    shadow_root_authorization["jouable_authorized"] = True
    cases.append(("shadow root authorization", shadow_root_authorization))

    unknown_root_promotion = copy.deepcopy(catalog)
    unknown_root_promotion["destination_advertisable"] = True
    cases.append(("unknown root promotion", unknown_root_promotion))

    unknown_top_authorization = copy.deepcopy(catalog)
    unknown_top_authorization["authorization"]["destination_advertisable"] = True
    cases.append(("unknown top-level authorization", unknown_top_authorization))

    unknown_row_authorization = copy.deepcopy(catalog)
    unknown_row_authorization["destinations"][0]["destination_advertisable"] = True
    cases.append(("unknown row authorization", unknown_row_authorization))

    missing_row_field = copy.deepcopy(catalog)
    del missing_row_field["destinations"][0]["source_sha256"]
    cases.append(("missing canonical row field", missing_row_field))

    stale_count = copy.deepcopy(catalog)
    stale_count["destination_count"] = len(stale_count["destinations"]) + 1
    cases.append(("stale destination count", stale_count))

    bool_count = copy.deepcopy(catalog)
    bool_count["destination_count"] = True
    cases.append(("boolean destination count", bool_count))

    string_count = copy.deepcopy(catalog)
    string_count["destination_count"] = str(len(string_count["destinations"]))
    cases.append(("string destination count", string_count))

    stale_mapped_cell_count = copy.deepcopy(catalog)
    stale_mapped_cell_count["mapped_cell_count"] = catalog["mapped_cell_count"] + 1
    cases.append(("stale mapped cell count", stale_mapped_cell_count))

    bool_mapped_cell_count = copy.deepcopy(catalog)
    bool_mapped_cell_count["mapped_cell_count"] = True
    cases.append(("boolean mapped cell count", bool_mapped_cell_count))

    string_mapped_cell_count = copy.deepcopy(catalog)
    string_mapped_cell_count["mapped_cell_count"] = str(catalog["mapped_cell_count"])
    cases.append(("string mapped cell count", string_mapped_cell_count))

    stale_source_document_count = copy.deepcopy(catalog)
    stale_source_document_count["source_document_count"] = catalog["source_document_count"] + 1
    cases.append(("stale source document count", stale_source_document_count))

    bool_source_document_count = copy.deepcopy(catalog)
    bool_source_document_count["source_document_count"] = True
    cases.append(("boolean source document count", bool_source_document_count))

    string_source_document_count = copy.deepcopy(catalog)
    string_source_document_count["source_document_count"] = str(catalog["source_document_count"])
    cases.append(("string source document count", string_source_document_count))

    blank_cell_id = copy.deepcopy(catalog)
    blank_cell_id["destinations"][0]["cell_id"] = ""
    cases.append(("blank cell id", blank_cell_id))

    blank_source_path = copy.deepcopy(catalog)
    blank_source_path["destinations"][0]["source_path"] = "  "
    cases.append(("blank source path", blank_source_path))

    grid_cell_drift = copy.deepcopy(catalog)
    grid_cell_drift["destinations"][0]["grid_cell_id"] = "E0_N0"
    cases.append(("grid cell identity drift", grid_cell_drift))

    manifest_path_drift = copy.deepcopy(catalog)
    manifest_path_drift["destinations"][0]["cell_manifest_path"] = "data/cell_manifests/other.json"
    cases.append(("cell manifest identity drift", manifest_path_drift))

    bbox_drift = copy.deepcopy(catalog)
    bbox_drift["destinations"][0]["cell_bbox"][2] += 1.0
    cases.append(("cell bbox identity drift", bbox_drift))

    crs_drift = copy.deepcopy(catalog)
    crs_drift["destinations"][0]["cell_crs"] = "EPSG:4326"
    cases.append(("cell CRS drift", crs_drift))

    for label, candidate in cases:
        try:
            validate(candidate)
        except ValueError:
            continue
        raise AssertionError(f"{label} mutation was accepted")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("catalog", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    catalog = _load(args.catalog)
    count = validate(catalog)
    if args.self_test:
        self_test(catalog)
    print(
        "ROAD_DESTINATION_READINESS_AUTHORIZATION_OK "
        f"destinations={count} all_authorizations_false=true "
        f"registered_not_rendered=true self_test={str(args.self_test).lower()} "
        "closed_root_schema=true closed_authorization_schema=true closed_destination_schema=true "
        "finite_json_required=true promotion_state_strings_bound=true destination_count_bound=true "
        "mapped_cell_count_bound=true source_document_count_bound=true aggregate_identity_nonempty=true "
        "cell_identity_tuple_bound=true promotion_fail_closed=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
