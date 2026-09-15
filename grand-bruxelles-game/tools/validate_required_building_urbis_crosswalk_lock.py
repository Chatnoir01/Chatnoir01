#!/usr/bin/env python3
"""Fail-close lock for the historical Bourse OSM -> UrbIS crosswalk.

This validator is deliberately network-free. It protects the already-recorded Bourse
crosswalk and official evidence identity independently of the document SHA-256. It
grants no runtime, render, collision, spawn or JOUABLE authorization.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, NoReturn

BOURSE_OSM_TYPE = "way"
BOURSE_OSM_ID = 13494623
EXPECTED_CROSSWALK: dict[str, Any] = {
    "urbis_inspire_id": "https://databrussels.be/id/building/1751663",
    "urbis_ref": "8186511",
    "urbis_crs": "EPSG:31370",
    "urbis_area_m2": 3368.0,
    "cross_check_accessed_at": "2026-08-12",
}
EXPECTED_EVIDENCE: dict[str, dict[str, Any]] = {
    "footprint": {
        "source": "official_urbis_plan",
        "inspire_id": "https://databrussels.be/id/building/1751663",
        "reference": "8186511",
        "crs": "EPSG:31370",
        "area_m2": 3368.0,
        "accessed_at": "2026-08-12",
    },
    "height": {
        "source": "official_urbis_3d_building_faces",
        "dataset_id": "e9ec2aa4-cffd-11ee-bccc-00090ffe0001",
        "building_solid_id": "https://databrussels.be/id/buildingsolid/617669",
        "crs": "EPSG:31370",
        "source_ground_z_m": 18.2459,
        "source_apex_z_m": 58.4012,
        "vertical_extent_m": 40.1553,
        "package_sha256": "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2",
        "accessed_at": "2026-08-12",
    },
    "roof": {
        "source": "official_urbis_3d_building_faces",
        "dataset_id": "e9ec2aa4-cffd-11ee-bccc-00090ffe0001",
        "building_solid_id": "https://databrussels.be/id/buildingsolid/617669",
        "crs": "EPSG:31370",
        "semantic_face_type": "ROOFSURFACE",
        "roof_face_count": 231,
        "building_faces_shp_sha256": "5371b8dfc65bb0565677ccbbeb0936444d827daba81a7e508de3d5f530536997",
        "accessed_at": "2026-08-12",
    },
}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"BOURSE_URBIS_CROSSWALK_LOCK_FAIL: {message}")


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def parse_finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        fail(f"non-finite decoded JSON number {value!r}")
    return parsed


def load_json(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        fail(f"cannot read source {path}: {exc}")
    try:
        text = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        fail(f"source is not strict UTF-8: {exc}")
    try:
        payload = json.loads(
            text,
            object_pairs_hook=reject_duplicate_object_keys,
            parse_float=parse_finite_float,
            parse_constant=lambda value: fail(f"non-finite JSON constant {value!r}"),
        )
    except (json.JSONDecodeError, ValueError, OverflowError) as exc:
        fail(f"invalid JSON: {exc}")
    if type(payload) is not dict:
        fail("source root must be an object")
    return payload


def find_bourse(payload: dict[str, Any]) -> dict[str, Any]:
    corridor = payload.get("corridor")
    if type(corridor) is not dict:
        fail("corridor must be an object")
    required = corridor.get("required_buildings")
    if type(required) is not list:
        fail("corridor.required_buildings must be an array")
    matches = [b for b in required if type(b) is dict and b.get("osm_type") == BOURSE_OSM_TYPE and b.get("osm_id") == BOURSE_OSM_ID]
    if len(matches) != 1:
        fail(f"historical Bourse UrbIS crosswalk drift: expected exactly one {BOURSE_OSM_TYPE}/{BOURSE_OSM_ID}, found {len(matches)}")
    return matches[0]


def validate_exact_map(observed: Any, expected: dict[str, Any], label: str) -> None:
    if type(observed) is not dict:
        fail(f"{label} must be an object")
    if set(observed) != set(expected):
        fail(f"{label} fields observed={sorted(observed)} required={sorted(expected)}")
    for field, required in expected.items():
        value = observed[field]
        if type(required) is float:
            if type(value) not in (int, float) or type(value) is bool or not math.isfinite(float(value)) or float(value) != required:
                fail(f"{label}.{field} observed={value!r} required={required!r}")
        elif value != required:
            fail(f"{label}.{field} observed={value!r} required={required!r}")


def validate(source: Path) -> None:
    building = find_bourse(load_json(source))
    for field, expected in EXPECTED_CROSSWALK.items():
        observed = building.get(field)
        if field == "urbis_area_m2":
            if type(observed) not in (int, float) or type(observed) is bool or not math.isfinite(float(observed)) or float(observed) != expected:
                fail(f"historical Bourse UrbIS crosswalk drift: {field} observed={observed!r} required={expected!r}")
        elif observed != expected:
            fail(f"historical Bourse UrbIS crosswalk drift: {field} observed={observed!r} required={expected!r}")

    evidence = building.get("evidence")
    if type(evidence) is not dict:
        fail("historical Bourse evidence must be an object")
    for rail, expected in EXPECTED_EVIDENCE.items():
        validate_exact_map(evidence.get(rail), expected, f"historical Bourse evidence.{rail}")
    if evidence.get("frontage") is not None:
        fail("historical Bourse evidence.frontage must remain null")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1] / "data" / "osm" / "vertical_slice_01.game.json")
    args = parser.parse_args()
    validate(args.source)
    print("BOURSE_URBIS_CROSSWALK_LOCK_OK osm=way/13494623 urbis=1751663 ref=8186511 crs=EPSG:31370 area_m2=3368 accessed_at=2026-08-12 evidence_identity=locked strict_finite_json=true network_used=false runtime_authorized=false jouable_promoted=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
