#!/usr/bin/env python3
"""Fail-close validation for the shipped road-destination source corpus.

This validator proves that compatible grand-bruxelles-osm-v1 documents under data/osm
match the committed allowlist and SHA-256 digests, retain the locked OSM attribution
and license, and have self-consistent corridor selection and source accounting. It does
not acquire data and grants no render/runtime/JOUABLE authorization.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
from typing import Any

LOCK_FORMAT = "grand-bruxelles-road-destination-source-lock-v1"
SOURCE_FORMAT = "grand-bruxelles-osm-v1"
SOURCE_ATTRIBUTION = "OpenStreetMap contributors via Overpass API"
SOURCE_LICENSE = "ODbL-1.0"
DEFAULT_LOCK_NAME = "road_destination_sources.lock.json"
COUNT_KEYS = ("roads", "drivable_roads", "buildings", "railways", "environment_points")
SELECTION_RADIUS_KEYS = ("roads", "buildings", "railways", "environment_points")
REQUIRED_CORRIDOR_ANCHORS = (
    ("midi", "Gare du Midi", -668.5, 627.84),
    ("anneessens", "Place Anneessens", -272.04, -217.07),
    ("bourse", "Bourse / Beurs", 81.54, -664.58),
    ("grand_place", "Grand-Place", 319.01, -535.2),
)
REQUIRED_CORRIDOR_ANCHOR_IDS = tuple(anchor[0] for anchor in REQUIRED_CORRIDOR_ANCHORS)
REQUIRED_BUILDING_APPROVAL_KEYS = ("footprint", "height", "roof", "frontage")
URBIS_CRS = "EPSG:31370"


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"ROAD_DESTINATION_SOURCE_LOCK_FAIL: {message}")


def is_sha256(value: Any) -> bool:
    return type(value) is str and len(value) == 64 and all(ch in "0123456789abcdef" for ch in value)


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def canonical_source_path(value: Any) -> str:
    if type(value) is not str or not value or value.strip() != value or "\\" in value:
        fail(f"non-canonical source path {value!r}")
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts or pure.as_posix() != value:
        fail(f"non-canonical source path {value!r}")
    if not value.startswith("data/osm/") or not value.endswith(".game.json"):
        fail(f"source path outside locked OSM corpus {value!r}")
    return value


def repository_root(source_root: Path) -> Path:
    source_root = source_root.resolve()
    if source_root.name != "osm" or source_root.parent.name != "data":
        fail(f"unexpected source root {source_root}")
    return source_root.parent.parent


def non_negative_count(value: Any, label: str) -> int:
    if type(value) is not int or value < 0:
        fail(f"{label} must be a non-negative integer")
    return value


def required_array(payload: dict[str, Any], key: str) -> list[Any]:
    value = payload.get(key)
    if type(value) is not list:
        fail(f"accounting {key} must be an array")
    return value


def canonical_nonempty_text(value: Any, label: str) -> str:
    if type(value) is not str or not value or value.strip() != value:
        fail(f"{label} must be a non-empty canonical string")
    return value


def finite_number(value: Any, label: str, *, positive: bool = False) -> float:
    if type(value) not in (int, float) or not math.isfinite(float(value)):
        fail(f"{label} must be a finite number")
    number = float(value)
    if positive and number <= 0.0:
        fail(f"{label} must be a finite positive number")
    return number


def validate_required_buildings(corridor: dict[str, Any]) -> None:
    required = corridor.get("required_buildings")
    if type(required) is not list or not required:
        fail("corridor.required_buildings must be a non-empty array")

    seen_osm_ids: set[tuple[str, int]] = set()
    for index, building in enumerate(required):
        label = f"corridor.required_buildings[{index}]"
        if type(building) is not dict:
            fail(f"{label} must be an object")

        osm_id = building.get("osm_id")
        if type(osm_id) is not int or osm_id <= 0:
            fail(f"{label}.osm_id must be a positive integer")
        osm_type = canonical_nonempty_text(building.get("osm_type"), f"{label}.osm_type")
        if osm_type not in {"node", "way", "relation"}:
            fail(f"{label}.osm_type must be node, way or relation")
        identity = (osm_type, osm_id)
        if identity in seen_osm_ids:
            fail(f"duplicate required-building OSM identity {identity!r}")
        seen_osm_ids.add(identity)

        anchor_id = canonical_nonempty_text(building.get("anchor_id"), f"{label}.anchor_id")
        if anchor_id not in REQUIRED_CORRIDOR_ANCHOR_IDS:
            fail(f"{label}.anchor_id is not a locked corridor anchor")
        canonical_nonempty_text(building.get("role"), f"{label}.role")
        canonical_nonempty_text(building.get("name"), f"{label}.name")

        source_url = canonical_nonempty_text(building.get("source_url"), f"{label}.source_url")
        expected_source_url = f"https://www.openstreetmap.org/{osm_type}/{osm_id}"
        if source_url != expected_source_url:
            fail(f"{label}.source_url must match the exact OSM identity")
        if building.get("source_license") != SOURCE_LICENSE:
            fail(f"{label}.source_license drift")

        urbis_inspire_id = canonical_nonempty_text(
            building.get("urbis_inspire_id"), f"{label}.urbis_inspire_id"
        )
        if not urbis_inspire_id.startswith("https://databrussels.be/id/building/"):
            fail(f"{label}.urbis_inspire_id must be an official Brussels building identifier")
        canonical_nonempty_text(building.get("urbis_ref"), f"{label}.urbis_ref")
        if building.get("urbis_crs") != URBIS_CRS:
            fail(f"{label}.urbis_crs must be {URBIS_CRS}")
        finite_number(building.get("urbis_area_m2"), f"{label}.urbis_area_m2", positive=True)
        canonical_nonempty_text(building.get("cross_check_accessed_at"), f"{label}.cross_check_accessed_at")

        approval = building.get("runtime_approval")
        if type(approval) is not dict or set(approval) != set(REQUIRED_BUILDING_APPROVAL_KEYS):
            fail(f"{label}.runtime_approval field set drift")
        for key in REQUIRED_BUILDING_APPROVAL_KEYS:
            if type(approval.get(key)) is not bool:
                fail(f"{label}.runtime_approval.{key} must be a boolean")

        evidence = building.get("evidence")
        if type(evidence) is not dict or set(evidence) != set(REQUIRED_BUILDING_APPROVAL_KEYS):
            fail(f"{label}.evidence field set drift")
        for key in REQUIRED_BUILDING_APPROVAL_KEYS:
            item = evidence.get(key)
            if approval[key] and type(item) is not dict:
                fail(f"{label}.runtime_approval.{key}=true requires evidence.{key}")
            if item is not None and type(item) is not dict:
                fail(f"{label}.evidence.{key} must be an object or null")

        canonical_nonempty_text(building.get("status"), f"{label}.status")


def validate_corridor_selection(payload: dict[str, Any]) -> None:
    corridor = payload.get("corridor")
    if type(corridor) is not dict:
        fail("corridor must be an object")

    canonical_nonempty_text(corridor.get("name"), "corridor.name")

    anchors = corridor.get("anchors")
    if type(anchors) is not list or not anchors:
        fail("corridor.anchors must be a non-empty array")
    seen_anchor_ids: set[str] = set()
    ordered_anchor_ids: list[str] = []
    for index, anchor in enumerate(anchors):
        if type(anchor) is not dict:
            fail(f"corridor.anchors[{index}] must be an object")
        anchor_id = canonical_nonempty_text(anchor.get("id"), f"corridor.anchors[{index}].id")
        if anchor_id in seen_anchor_ids:
            fail(f"duplicate corridor anchor id {anchor_id!r}")
        seen_anchor_ids.add(anchor_id)
        ordered_anchor_ids.append(anchor_id)
        canonical_nonempty_text(anchor.get("name"), f"corridor.anchors[{index}].name")
        finite_number(anchor.get("x"), f"corridor.anchors[{index}].x")
        finite_number(anchor.get("z"), f"corridor.anchors[{index}].z")

    if tuple(ordered_anchor_ids) != REQUIRED_CORRIDOR_ANCHOR_IDS:
        fail(
            "corridor anchor order drift: "
            f"observed={ordered_anchor_ids!r} required={list(REQUIRED_CORRIDOR_ANCHOR_IDS)!r}"
        )

    for index, (anchor, expected) in enumerate(zip(anchors, REQUIRED_CORRIDOR_ANCHORS, strict=True)):
        expected_id, expected_name, expected_x, expected_z = expected
        observed_name = anchor.get("name")
        observed_x = float(anchor.get("x"))
        observed_z = float(anchor.get("z"))
        if observed_name != expected_name:
            fail(
                f"corridor anchor name drift {expected_id}: "
                f"observed={observed_name!r} required={expected_name!r}"
            )
        if observed_x != expected_x or observed_z != expected_z:
            fail(
                f"corridor anchor coordinate drift {expected_id}: "
                f"observed=[{observed_x},{observed_z}] required=[{expected_x},{expected_z}]"
            )

    validate_required_buildings(corridor)

    selection_radius = corridor.get("selection_radius_m")
    if type(selection_radius) is not dict:
        fail("corridor.selection_radius_m must be an object")
    if set(selection_radius) != set(SELECTION_RADIUS_KEYS):
        fail("corridor.selection_radius_m field set drift")
    for key in SELECTION_RADIUS_KEYS:
        finite_number(
            selection_radius.get(key),
            f"corridor.selection_radius_m.{key}",
            positive=True,
        )


def canonical_road_text(
    index: int,
    field: str,
    value: Any,
    *,
    optional: bool = False,
    allow_empty: bool = False,
) -> str | None:
    if optional and value is None:
        return None
    if type(value) is not str or value.strip() != value or (not allow_empty and not value):
        qualifier = "canonical string (empty permitted)" if allow_empty else "non-empty canonical string"
        fail(f"roads[{index}].{field} must be a {qualifier}")
    return value


def validate_road_points(index: int, value: Any) -> None:
    if type(value) is not list or len(value) < 2:
        fail(f"roads[{index}].points must be an array with at least two points")
    distinct: set[tuple[float, float]] = set()
    for point_index, point in enumerate(value):
        if type(point) is not list or len(point) != 2:
            fail(f"roads[{index}].points[{point_index}] must be a [x,z] pair")
        coordinates: list[float] = []
        for coordinate_index, coordinate in enumerate(point):
            if type(coordinate) not in (int, float) or not math.isfinite(float(coordinate)):
                fail(
                    f"roads[{index}].points[{point_index}][{coordinate_index}] "
                    "must be a finite numeric coordinate"
                )
            coordinates.append(float(coordinate))
        distinct.add((coordinates[0], coordinates[1]))
    if len(distinct) < 2:
        fail(f"roads[{index}].points must contain at least two distinct coordinates")


def validate_source_payload(path: str, payload: dict[str, Any]) -> None:
    if payload.get("format") != SOURCE_FORMAT:
        fail(f"source format drift {path}")
    if payload.get("source") != SOURCE_ATTRIBUTION:
        fail(f"source attribution drift {path}")
    if payload.get("license") != SOURCE_LICENSE:
        fail(f"source license drift {path}")

    validate_corridor_selection(payload)

    roads = required_array(payload, "roads")
    buildings = required_array(payload, "buildings")
    railways = required_array(payload, "railways")
    environment_points = required_array(payload, "environment_points")

    drivable_roads = 0
    seen_road_osm_ids: set[int] = set()
    for index, road in enumerate(roads):
        if type(road) is not dict:
            fail(f"accounting roads[{index}] must be an object")
        osm_id = road.get("osm_id")
        if type(osm_id) is not int or osm_id <= 0:
            fail(f"roads[{index}].osm_id must be a positive integer")
        if osm_id in seen_road_osm_ids:
            fail(f"duplicate roads[].osm_id {osm_id}")
        seen_road_osm_ids.add(osm_id)
        canonical_road_text(index, "name", road.get("name"), optional=True, allow_empty=True)
        canonical_road_text(index, "class", road.get("class"))
        drivable = road.get("drivable")
        if type(drivable) is not bool:
            fail(f"roads[{index}].drivable must be a boolean")
        width = road.get("width")
        if (
            type(width) not in (int, float)
            or not math.isfinite(float(width))
            or float(width) <= 0.0
        ):
            fail(f"roads[{index}].width must be a finite positive number")
        validate_road_points(index, road.get("points"))
        if drivable:
            drivable_roads += 1

    materialized = {
        "roads": len(roads),
        "drivable_roads": drivable_roads,
        "buildings": len(buildings),
        "railways": len(railways),
        "environment_points": len(environment_points),
    }

    stats = payload.get("stats")
    if type(stats) is not dict:
        fail(f"accounting stats missing {path}")
    for key in COUNT_KEYS:
        selected = non_negative_count(stats.get(key), f"accounting stats.{key}")
        if selected != materialized[key]:
            fail(
                f"accounting mismatch {path} {key}: "
                f"stats={selected} materialized={materialized[key]}"
            )

    source_stats = payload.get("source_stats")
    if type(source_stats) is not dict:
        fail(f"source_stats missing {path}")
    totals = {
        key: non_negative_count(source_stats.get(key), f"source_stats.{key}")
        for key in COUNT_KEYS
    }
    if totals["drivable_roads"] > totals["roads"]:
        fail(f"source_stats invalid {path}: drivable_roads > roads")
    for key in COUNT_KEYS:
        if materialized[key] > totals[key]:
            fail(
                f"source_stats invalid {path}: selected {key}={materialized[key]} "
                f"exceeds source total={totals[key]}"
            )


def load_lock(source_root: Path, lock_path: Path | None = None) -> dict[str, str]:
    source_root = source_root.resolve()
    repo_root = repository_root(source_root)
    canonical_lock = (source_root / DEFAULT_LOCK_NAME).resolve()
    lock_path = (lock_path or canonical_lock).resolve()
    if lock_path != canonical_lock:
        fail(f"lock path must be canonical {canonical_lock}, got {lock_path}")
    try:
        raw_text = lock_path.read_text(encoding="utf-8")
        payload = json.loads(raw_text, object_pairs_hook=reject_duplicate_object_keys)
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"invalid lock document {lock_path}: {exc}")
    if type(payload) is not dict:
        fail("lock root must be an object")
    expected_fields = {
        "format", "source_format", "source", "license", "evidence_artifact_id",
        "evidence_catalog_sha256", "documents",
    }
    if set(payload) != expected_fields:
        fail("lock field set drift")
    if payload.get("format") != LOCK_FORMAT or payload.get("source_format") != SOURCE_FORMAT:
        fail("lock format drift")
    if payload.get("source") != SOURCE_ATTRIBUTION:
        fail("source attribution drift")
    if payload.get("license") != SOURCE_LICENSE:
        fail("source license drift")
    if type(payload.get("evidence_artifact_id")) is not int or payload["evidence_artifact_id"] <= 0:
        fail("invalid evidence artifact id")
    if not is_sha256(payload.get("evidence_catalog_sha256")):
        fail("invalid evidence catalog SHA256")
    documents = payload.get("documents")
    if type(documents) is not dict or not documents:
        fail("locked source documents missing")

    locked: dict[str, str] = {}
    for raw_path, raw_digest in documents.items():
        path = canonical_source_path(raw_path)
        if not is_sha256(raw_digest):
            fail(f"invalid locked SHA256 for {path}")
        file_path = (repo_root / path).resolve()
        try:
            file_path.relative_to(source_root)
        except ValueError:
            fail(f"locked source escapes source root {path}")
        if not file_path.is_file():
            fail(f"locked source document missing {path}")
        observed = hashlib.sha256(file_path.read_bytes()).hexdigest()
        if observed != raw_digest:
            fail(f"locked source document SHA256 drift {path}: {observed} != {raw_digest}")
        locked[path] = raw_digest
    return dict(sorted(locked.items()))


def discover_compatible_documents(source_root: Path) -> dict[str, str]:
    source_root = source_root.resolve()
    repo_root = repository_root(source_root)
    compatible: dict[str, str] = {}
    for path in sorted(source_root.rglob("*.game.json")):
        if not path.is_file():
            continue
        try:
            raw = path.read_bytes()
            payload = json.loads(
                raw.decode("utf-8"),
                object_pairs_hook=reject_duplicate_object_keys,
            )
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            fail(f"invalid source JSON {path}: {exc}")
        if type(payload) is not dict or payload.get("format") != SOURCE_FORMAT:
            continue
        relative = canonical_source_path(path.resolve().relative_to(repo_root).as_posix())
        validate_source_payload(relative, payload)
        compatible[relative] = hashlib.sha256(raw).hexdigest()
    return dict(sorted(compatible.items()))


def validate(source_root: Path, lock_path: Path | None = None) -> dict[str, str]:
    locked = load_lock(source_root, lock_path)
    discovered = discover_compatible_documents(source_root)
    if set(discovered) != set(locked):
        unexpected = sorted(set(discovered) - set(locked))
        missing = sorted(set(locked) - set(discovered))
        fail(f"compatible source set drift unexpected={unexpected} missing={missing}")
    for path, digest in locked.items():
        if discovered[path] != digest:
            fail(f"compatible source SHA256 drift {path}: {discovered[path]} != {digest}")
    return locked


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-root",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "data" / "osm",
    )
    parser.add_argument("--lock", type=Path)
    args = parser.parse_args()
    locked = validate(args.source_root, args.lock)
    print(
        f"ROAD_DESTINATION_SOURCE_LOCK_OK: documents={len(locked)} "
        "provenance=true corridor_selection=true anchor_coordinates_locked=true "
        "accounting=true network_used=false"
    )
    for path, digest in locked.items():
        print(f"ROAD_DESTINATION_SOURCE_LOCK_DOCUMENT: {path} sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
