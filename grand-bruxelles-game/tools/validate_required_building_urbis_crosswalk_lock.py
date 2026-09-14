#!/usr/bin/env python3
"""Fail-close lock for the historical Bourse OSM -> UrbIS crosswalk.

This validator is deliberately network-free. It protects the already-recorded Bourse
crosswalk independently of the document SHA-256 so a recomputed digest cannot silently
replace the official UrbIS identity/evidence tuple. It grants no runtime, render,
collision, spawn or JOUABLE authorization.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

BOURSE_OSM_TYPE = "way"
BOURSE_OSM_ID = 13494623
EXPECTED_CROSSWALK: dict[str, Any] = {
    "urbis_inspire_id": "https://databrussels.be/id/building/1751663",
    "urbis_ref": "8186511",
    "urbis_crs": "EPSG:31370",
    "urbis_area_m2": 3368.0,
    "cross_check_accessed_at": "2026-08-12",
}


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"BOURSE_URBIS_CROSSWALK_LOCK_FAIL: {message}")


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


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
            parse_constant=lambda value: fail(f"non-finite JSON constant {value!r}"),
        )
    except json.JSONDecodeError as exc:
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

    matches: list[dict[str, Any]] = []
    for building in required:
        if type(building) is not dict:
            continue
        if building.get("osm_type") == BOURSE_OSM_TYPE and building.get("osm_id") == BOURSE_OSM_ID:
            matches.append(building)
    if len(matches) != 1:
        fail(
            "historical Bourse UrbIS crosswalk drift: expected exactly one "
            f"{BOURSE_OSM_TYPE}/{BOURSE_OSM_ID}, found {len(matches)}"
        )
    return matches[0]


def validate(source: Path) -> None:
    building = find_bourse(load_json(source))

    for field, expected in EXPECTED_CROSSWALK.items():
        observed = building.get(field)
        if field == "urbis_area_m2":
            if type(observed) not in (int, float) or not math.isfinite(float(observed)):
                fail(
                    "historical Bourse UrbIS crosswalk drift: "
                    f"{field} must be the finite historical value {expected!r}"
                )
            if float(observed) != expected:
                fail(
                    "historical Bourse UrbIS crosswalk drift: "
                    f"{field} observed={observed!r} required={expected!r}"
                )
            continue
        if observed != expected:
            fail(
                "historical Bourse UrbIS crosswalk drift: "
                f"{field} observed={observed!r} required={expected!r}"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "data" / "osm" / "vertical_slice_01.game.json",
    )
    args = parser.parse_args()
    validate(args.source)
    print(
        "BOURSE_URBIS_CROSSWALK_LOCK_OK "
        "osm=way/13494623 urbis=1751663 ref=8186511 crs=EPSG:31370 "
        "area_m2=3368 accessed_at=2026-08-12 network_used=false "
        "runtime_authorized=false jouable_promoted=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
