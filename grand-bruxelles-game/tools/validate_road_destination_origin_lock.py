#!/usr/bin/env python3
"""Fail-close validation for the locked OSM game-frame origin.

This validator is deliberately network-free and independent of the source document
SHA-256. Recomputing a source digest must not authorize a different coordinate frame.
It grants no runtime, render, collision, spawn or JOUABLE authorization.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

EXPECTED_ORIGIN = {"lat": 50.8419, "lon": 4.348}


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"ROAD_DESTINATION_ORIGIN_LOCK_FAIL: {message}")


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def validate_origin(payload: dict[str, Any]) -> None:
    origin = payload.get("origin")
    if type(origin) is not dict:
        fail("origin must be an object")
    if set(origin) != set(EXPECTED_ORIGIN):
        fail(
            "origin field set drift: "
            f"observed={sorted(origin)!r} required={sorted(EXPECTED_ORIGIN)!r}"
        )

    for axis, expected in EXPECTED_ORIGIN.items():
        value = origin.get(axis)
        if type(value) not in (int, float) or not math.isfinite(float(value)):
            fail(f"origin.{axis} must be a finite number")
        observed = float(value)
        if observed != expected:
            fail(f"origin.{axis} drift: observed={observed!r} required={expected!r}")


def validate(source: Path) -> None:
    try:
        payload = json.loads(
            source.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_object_keys,
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"invalid source JSON {source}: {exc}")
    if type(payload) is not dict:
        fail("source root must be an object")
    validate_origin(payload)


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
        "ROAD_DESTINATION_ORIGIN_LOCK_OK "
        "lat=50.8419 lon=4.348 exact_schema=true digest_independent=true network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
