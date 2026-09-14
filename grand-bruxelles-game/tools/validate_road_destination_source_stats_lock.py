#!/usr/bin/env python3
"""Fail-close lock for historical OSM acquisition totals.

This validator is intentionally network-free and independent of the document digest.
It grants no render/runtime/collision/JOUABLE authorization.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

EXPECTED_SOURCE_STATS = {
    "roads": 6114,
    "drivable_roads": 1330,
    "buildings": 8728,
    "railways": 536,
    "environment_points": 3564,
}


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"ROAD_DESTINATION_SOURCE_STATS_LOCK_FAIL: {message}")


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def validate(source_path: Path) -> None:
    try:
        payload = json.loads(
            source_path.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_object_keys,
        )
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"invalid source document {source_path}: {exc}")
    if type(payload) is not dict:
        fail("source root must be an object")

    observed = payload.get("source_stats")
    if type(observed) is not dict:
        fail("source_stats must be an object")
    if set(observed) != set(EXPECTED_SOURCE_STATS):
        fail(
            "source_stats field set drift: "
            f"observed={sorted(observed)!r} required={sorted(EXPECTED_SOURCE_STATS)!r}"
        )

    for key, expected in EXPECTED_SOURCE_STATS.items():
        value = observed.get(key)
        if type(value) is not int or value < 0:
            fail(f"source_stats.{key} must be a non-negative integer")
        if value != expected:
            fail(
                f"historical source total drift {key}: "
                f"observed={value} required={expected}"
            )

    if observed["drivable_roads"] > observed["roads"]:
        fail("source_stats invalid: drivable_roads > roads")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    args = parser.parse_args()
    validate(args.source.resolve())
    print(
        "ROAD_DESTINATION_SOURCE_STATS_LOCK_OK "
        "roads=6114 drivable_roads=1330 buildings=8728 railways=536 environment_points=3564 "
        "network_used=false authorization=none"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
