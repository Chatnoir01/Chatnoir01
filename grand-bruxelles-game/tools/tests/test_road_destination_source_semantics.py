#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "tools" / "validate_road_destination_source_semantics.py"
READINESS = ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json"

spec = importlib.util.spec_from_file_location("road_destination_source_semantics", VALIDATOR)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def _readiness() -> dict:
    return json.loads(READINESS.read_text(encoding="utf-8"))


def _assert_semantic_drift_fails(field: str, forged: object) -> None:
    readiness = _readiness()
    destination = readiness["destinations"][0]
    original = destination[field]
    assert forged != original
    destination[field] = forged
    try:
        module.validate_readiness(readiness)
    except SystemExit as exc:
        assert "destination source semantic drift" in str(exc)
        assert field in str(exc)
    else:
        raise AssertionError(
            f"destination {field} could drift away from exact OSM source truth: "
            f"{original!r} -> {forged!r}"
        )


def test_real_destination_semantics_match_exact_source() -> None:
    result = module.validate_readiness(_readiness())
    assert result["destination_count"] == 96
    assert result["source_road_count"] == 140


def test_destination_road_name_must_match_exact_source_record() -> None:
    _assert_semantic_drift_fails("road_name", "Forged corridor road")


def test_destination_road_class_must_match_exact_source_record() -> None:
    _assert_semantic_drift_fails("road_class", "motorway")


def test_destination_road_width_must_match_exact_source_record() -> None:
    _assert_semantic_drift_fails("road_width_m", 99.0)


def test_destination_source_point_count_must_match_exact_source_record() -> None:
    readiness = _readiness()
    current = readiness["destinations"][0]["source_local_point_count"]
    _assert_semantic_drift_fails("source_local_point_count", current + 1)


def test_destination_source_points_hash_must_match_exact_source_record() -> None:
    _assert_semantic_drift_fails("source_points_sha256", "0" * 64)


def test_destination_source_local_bbox_must_match_exact_source_record() -> None:
    readiness = _readiness()
    bbox = list(readiness["destinations"][0]["source_local_bbox"])
    bbox[0] -= 1.0
    _assert_semantic_drift_fails("source_local_bbox", bbox)
