#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any

EXPECTED_SCHEMA = "grand-bruxelles-road-destination-readiness-catalog-v1"


class DuplicateJsonKey(ValueError):
    pass


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, value in pairs:
        if key in out:
            raise DuplicateJsonKey(f"duplicate JSON key: {key}")
        out[key] = value
    return out


def _finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite JSON number: {value}")
    return parsed


def _load_strict(path: Path) -> dict[str, Any]:
    raw = path.read_text(encoding="utf-8")
    parsed = json.loads(
        raw,
        object_pairs_hook=_strict_object,
        parse_float=_finite_float,
        parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"non-finite JSON number: {value}")),
    )
    if not isinstance(parsed, dict):
        raise ValueError("catalog root must be an object")
    return parsed


def validate_catalog(catalog: dict[str, Any]) -> tuple[int, int]:
    if catalog.get("schema") != EXPECTED_SCHEMA:
        raise ValueError("unexpected catalog schema")
    rows = catalog.get("destinations")
    if not isinstance(rows, list) or not rows:
        raise ValueError("catalog destinations missing")
    destination_count = catalog.get("destination_count")
    if type(destination_count) is not int:
        raise ValueError("catalog destination_count must be an integer")
    if destination_count != len(rows):
        raise ValueError("catalog destination_count drifted")

    seen_ids: set[str] = set()
    seen_osm: set[int] = set()
    for index, raw in enumerate(rows):
        if not isinstance(raw, dict):
            raise ValueError(f"destination row {index} must be an object")
        destination_id = raw.get("destination_id")
        road_osm_id = raw.get("road_osm_id")
        if not isinstance(destination_id, str) or not destination_id:
            raise ValueError(f"destination row {index} has invalid destination_id")
        if not isinstance(road_osm_id, int) or isinstance(road_osm_id, bool) or road_osm_id <= 0:
            raise ValueError(f"destination row {index} has invalid road_osm_id")
        if destination_id != f"road-{road_osm_id}":
            raise ValueError(f"destination identity mismatch at row {index}")
        if destination_id in seen_ids:
            raise ValueError(f"duplicate destination_id: {destination_id}")
        if road_osm_id in seen_osm:
            raise ValueError(f"duplicate road_osm_id: {road_osm_id}")
        seen_ids.add(destination_id)
        seen_osm.add(road_osm_id)
    return len(seen_ids), len(seen_osm)


def self_test(catalog: dict[str, Any]) -> None:
    validate_catalog(catalog)
    rows = catalog["destinations"]
    witness = copy.deepcopy(rows[0])

    duplicate_row = copy.deepcopy(catalog)
    duplicate_row["destinations"].append(witness)
    duplicate_row["destination_count"] += 1
    try:
        validate_catalog(duplicate_row)
    except ValueError as exc:
        if "duplicate destination_id" not in str(exc):
            raise AssertionError(f"wrong duplicate-row rejection: {exc}") from exc
    else:
        raise AssertionError("duplicate destination row was accepted")

    alias_collision = copy.deepcopy(catalog)
    if len(alias_collision["destinations"]) < 2:
        raise AssertionError("catalog needs at least two rows for alias collision self-test")
    alias_collision["destinations"][1]["road_osm_id"] = witness["road_osm_id"]
    alias_collision["destinations"][1]["destination_id"] = f"road-{witness['road_osm_id']}"
    try:
        validate_catalog(alias_collision)
    except ValueError as exc:
        if "duplicate destination_id" not in str(exc) and "duplicate road_osm_id" not in str(exc):
            raise AssertionError(f"wrong alias-collision rejection: {exc}") from exc
    else:
        raise AssertionError("duplicate road identity alias was accepted")

    bool_count = copy.deepcopy(catalog)
    bool_count["destinations"] = [copy.deepcopy(witness)]
    bool_count["destination_count"] = True
    try:
        validate_catalog(bool_count)
    except ValueError as exc:
        if "destination_count" not in str(exc):
            raise AssertionError(f"wrong boolean-count rejection: {exc}") from exc
    else:
        raise AssertionError("boolean destination_count was accepted as integer count 1")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("catalog", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    catalog = _load_strict(args.catalog)
    unique_destination_ids, unique_osm_ids = validate_catalog(catalog)
    if args.self_test:
        self_test(catalog)
    print(
        "ROAD_DESTINATION_READINESS_UNIQUE_IDENTITY_OK "
        f"destinations={unique_destination_ids} osm_ids={unique_osm_ids} "
        f"self_test={str(args.self_test).lower()} duplicate_identity_fail_closed=true "
        "finite_json_required=true destination_count_type_bound=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
