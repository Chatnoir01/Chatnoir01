#!/usr/bin/env python3
"""Fail-closed contract for automatic road spawn building source geometry.

The road direct-entry resolver uses source building footprints to reject unsafe
spawn/view sightlines. Those footprints are authoritative source geometry and
must therefore obey the same exact numeric boundary as road points: two finite
JSON numbers, never strings/bools/coercions, and never silently dropped points.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parents[2]
INDEX_PATH = PROJECT_ROOT / "data/runtime/road_destination_runtime_index.json"
EXPECTED_INDEX_FORMAT = "grand-bruxelles-road-runtime-index-v1"


def _exact_point(raw: Any) -> bool:
    if not isinstance(raw, list) or len(raw) != 2:
        return False
    for value in raw:
        # bool is an int subclass in Python; reject it explicitly to mirror the
        # Godot TYPE_INT/TYPE_FLOAT boundary rather than Python coercion.
        if isinstance(value, bool) or type(value) not in (int, float):
            return False
        if not math.isfinite(float(value)):
            return False
    return True


def _exact_buildings(document: Any) -> bool:
    if not isinstance(document, dict):
        return False
    buildings = document.get("buildings")
    if not isinstance(buildings, list):
        return False
    for building in buildings:
        if not isinstance(building, dict):
            return False
        footprint = building.get("footprint")
        if not isinstance(footprint, list) or len(footprint) < 3:
            return False
        if not all(_exact_point(point) for point in footprint):
            return False
    return True


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _assert_mutation_regressions(sample_document: dict[str, Any]) -> None:
    buildings = sample_document.get("buildings")
    if not isinstance(buildings, list) or not buildings:
        raise AssertionError("source document must provide at least one building for regression mutation")
    footprint = buildings[0].get("footprint") if isinstance(buildings[0], dict) else None
    if not isinstance(footprint, list) or not footprint or not _exact_point(footprint[0]):
        raise AssertionError("first building must expose an exact source point for regression mutation")

    bad_values = ["1.0", True, None, float("nan"), float("inf"), float("-inf")]
    for bad in bad_values:
        mutated = copy.deepcopy(sample_document)
        mutated["buildings"][0]["footprint"][0][0] = bad
        if _exact_buildings(mutated):
            raise AssertionError(f"coercible/non-finite building coordinate was accepted: {bad!r}")

    mutated = copy.deepcopy(sample_document)
    mutated["buildings"][0]["footprint"][0] = [footprint[0][0]]
    if _exact_buildings(mutated):
        raise AssertionError("short building point was accepted")

    mutated = copy.deepcopy(sample_document)
    mutated["buildings"][0]["footprint"] = mutated["buildings"][0]["footprint"][:2]
    if _exact_buildings(mutated):
        raise AssertionError("degenerate building footprint was accepted")


def main() -> None:
    index = _load_json(INDEX_PATH)
    if not isinstance(index, dict) or index.get("format") != EXPECTED_INDEX_FORMAT:
        raise AssertionError("automatic-road runtime index format drifted")
    if index.get("source_lookup_only") is not True:
        raise AssertionError("automatic-road runtime index must remain source_lookup_only")

    authorization = index.get("authorization")
    if not isinstance(authorization, dict) or authorization.get("source_lookup_only") is not True:
        raise AssertionError("automatic-road authorization boundary drifted")
    for forbidden in (
        "render_authorized",
        "collision_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
        "jouable_authorized",
    ):
        if authorization.get(forbidden) is not False:
            raise AssertionError(f"{forbidden} must remain false in source index")

    documents = index.get("documents")
    if not isinstance(documents, list) or not documents:
        raise AssertionError("runtime index has no source documents")

    checked = 0
    mutation_sample: dict[str, Any] | None = None
    for descriptor in documents:
        if not isinstance(descriptor, dict):
            raise AssertionError("runtime index document descriptor is not an object")
        rel = descriptor.get("path")
        expected_sha = descriptor.get("sha256")
        if not isinstance(rel, str) or not rel.strip():
            raise AssertionError("runtime index source path missing")
        if not isinstance(expected_sha, str) or len(expected_sha) != 64:
            raise AssertionError(f"runtime index sha256 malformed for {rel!r}")

        source_path = PROJECT_ROOT / rel.removeprefix("res://").lstrip("/")
        if not source_path.is_file():
            raise AssertionError(f"indexed source document missing: {source_path}")
        actual_sha = _sha256(source_path)
        if actual_sha.lower() != expected_sha.lower():
            raise AssertionError(
                f"indexed source hash mismatch for {rel}: expected={expected_sha} actual={actual_sha}"
            )

        document = _load_json(source_path)
        if not _exact_buildings(document):
            raise AssertionError(
                f"automatic-road source building boundary is not exact/fail-closed: {rel}"
            )
        checked += 1
        if mutation_sample is None and isinstance(document, dict) and document.get("buildings"):
            mutation_sample = document

    if checked != len(documents):
        raise AssertionError("not every indexed automatic-road source document was checked")
    if mutation_sample is None:
        raise AssertionError("no indexed building source available for mutation regression")
    _assert_mutation_regressions(mutation_sample)

    print(
        "AUTOMATIC_ROAD_BUILDING_SOURCE_BOUNDARY_OK: "
        f"documents={checked} exact_points=true hash_pinned=true mutation_regression=true"
    )


if __name__ == "__main__":
    main()
