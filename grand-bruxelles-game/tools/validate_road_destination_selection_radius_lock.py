#!/usr/bin/env python3
"""Fail-close the historical corridor selection radii independently of source digests."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

SOURCE_FORMAT = "grand-bruxelles-osm-v1"
SOURCE_ATTRIBUTION = "OpenStreetMap contributors via Overpass API"
SOURCE_LICENSE = "ODbL-1.0"
EXPECTED_RADII = {
    "roads": 170.0,
    "buildings": 130.0,
    "railways": 180.0,
    "environment_points": 130.0,
}


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"ROAD_DESTINATION_SELECTION_RADIUS_LOCK_FAIL: {message}")


def finite_number(value: Any, label: str) -> float:
    if type(value) not in (int, float) or not math.isfinite(float(value)):
        fail(f"{label} must be a finite number")
    return float(value)


def validate_source_payload(payload: Any) -> dict[str, float]:
    if type(payload) is not dict:
        fail("source root must be an object")
    if payload.get("format") != SOURCE_FORMAT:
        fail("source format drift")
    if payload.get("source") != SOURCE_ATTRIBUTION:
        fail("source attribution drift")
    if payload.get("license") != SOURCE_LICENSE:
        fail("source license drift")

    corridor = payload.get("corridor")
    if type(corridor) is not dict:
        fail("corridor must be an object")
    radii = corridor.get("selection_radius_m")
    if type(radii) is not dict or set(radii) != set(EXPECTED_RADII):
        fail("corridor.selection_radius_m field set drift")

    observed: dict[str, float] = {}
    for key, expected in EXPECTED_RADII.items():
        value = finite_number(radii.get(key), f"corridor.selection_radius_m.{key}")
        if value != expected:
            fail(
                f"corridor.selection_radius_m.{key} drift: "
                f"observed={value:g} required={expected:g}"
            )
        observed[key] = value
    return observed


def validate(path: Path) -> dict[str, float]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"invalid source JSON {path}: {exc}")
    return validate_source_payload(payload)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "data" / "osm" / "vertical_slice_01.game.json",
    )
    args = parser.parse_args()
    observed = validate(args.source)
    print(
        "ROAD_DESTINATION_SELECTION_RADIUS_LOCK_OK "
        f"roads={observed['roads']:g} buildings={observed['buildings']:g} "
        f"railways={observed['railways']:g} environment_points={observed['environment_points']:g} "
        "historical_selection_semantics_pinned=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
