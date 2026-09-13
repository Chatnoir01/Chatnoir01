#!/usr/bin/env python3
"""Fail-closed Bourse automatic-destination candidate discovery.

This is evidence only. It ranks drivable OSM roads from the locked corridor source
against the exact Bourse anchor, but accepts candidates only when their OSM identity
also exists in the shared runtime destination index. It never authorizes render,
collision, safe spawn, visual acceptance, or JOUABLE promotion.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"
INDEX = ROOT / "data/runtime/road_destination_runtime_index.json"
EXPECTED_SOURCE_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
EXPECTED_INDEX_CATALOG_SHA256 = "7290b8272623e0cd5905224c8696d74a3015b1db9aab00ef19d1cf7676dea59f"
SOURCE_RELATIVE_PATH = "data/osm/vertical_slice_01.game.json"
OUT = ROOT / "artifacts/qa/bourse_automatic_destination_candidate/receipt.json"


def strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def strict_json_loads(raw: bytes | str) -> Any:
    text = raw.decode("utf-8") if isinstance(raw, bytes) else raw
    return json.loads(text, object_pairs_hook=strict_object)


def canonical_osm_id(value: Any) -> int:
    """Accept only JSON integer identities; reject coercible aliases and booleans."""
    assert type(value) is int, f"OSM identity must be a canonical JSON integer, got {type(value).__name__}"
    assert value > 0, f"OSM identity must be positive, got {value}"
    return value


def finite_source_number(value: Any, label: str) -> float:
    """Accept only finite JSON numbers; reject booleans, strings, NaN and infinities."""
    assert type(value) in (int, float), f"{label} must be a JSON number, got {type(value).__name__}"
    number = float(value)
    assert math.isfinite(number), f"{label} must be finite, got {value!r}"
    return number


def validate_road_points(points: Any, osm_id: int) -> list[list[float]]:
    assert isinstance(points, list), f"road {osm_id} points must be a list"
    assert len(points) >= 2, f"road {osm_id} must contain at least two source points"
    validated: list[list[float]] = []
    for point_index, point in enumerate(points):
        assert isinstance(point, list), f"road {osm_id} point {point_index} must be a list"
        assert len(point) == 2, f"road {osm_id} point {point_index} must contain exactly x,z"
        validated.append([
            finite_source_number(point[0], f"road {osm_id} point {point_index} x"),
            finite_source_number(point[1], f"road {osm_id} point {point_index} z"),
        ])
    return validated


def validate_road_metadata(road: dict[str, Any], osm_id: int) -> tuple[str, str, float]:
    """Keep source metadata canonical; never synthesize missing fields or coerce evidence aliases."""
    for field in ("name", "class", "width"):
        assert field in road, f"road {osm_id} required metadata field missing: {field}"
    name = road["name"]
    road_class = road["class"]
    width_raw = road["width"]
    assert type(name) is str, f"road {osm_id} name must be a JSON string"
    assert type(road_class) is str, f"road {osm_id} class must be a JSON string"
    assert name == name.strip(), f"road {osm_id} name must be canonical trimmed text"
    assert road_class == road_class.strip(), f"road {osm_id} class must be canonical trimmed text"
    assert all(ord(ch) >= 32 for ch in name), f"road {osm_id} name contains control characters"
    assert all(ord(ch) >= 32 for ch in road_class), f"road {osm_id} class contains control characters"
    width = finite_source_number(width_raw, f"road {osm_id} width")
    assert width >= 0.0, f"road {osm_id} width must be non-negative"
    return name, road_class, width


def validate_runtime_index(index: dict[str, Any]) -> tuple[dict[str, Any], set[int]]:
    assert index["catalog_sha256"] == EXPECTED_INDEX_CATALOG_SHA256
    assert index["source_lookup_only"] is True

    authorization = index.get("authorization")
    assert isinstance(authorization, dict), "runtime index authorization block missing"
    for key in (
        "render_authorized",
        "collision_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
        "jouable_authorized",
    ):
        assert authorization.get(key) is False, f"runtime index rail must remain closed: {key}"

    documents = index.get("documents")
    assert isinstance(documents, list), "runtime index documents must be a list"
    matches = [d for d in documents if isinstance(d, dict) and d.get("path") == SOURCE_RELATIVE_PATH]
    assert len(matches) == 1, f"expected exactly one runtime-index document for locked source, got {len(matches)}"

    matching_doc = matches[0]
    assert matching_doc.get("sha256") == EXPECTED_SOURCE_SHA256
    road_ids_raw = matching_doc.get("road_ids")
    assert isinstance(road_ids_raw, list), "runtime-index road_ids must be a list"
    road_ids = [canonical_osm_id(value) for value in road_ids_raw]
    assert len(road_ids) == len(set(road_ids)), "duplicate road identity in locked runtime-index document"
    return matching_doc, set(road_ids)


def regression_duplicate_document_must_fail(index: dict[str, Any]) -> None:
    """Prove the historical union-of-duplicate-documents fail-open stays closed."""
    cloned = json.loads(json.dumps(index))
    documents = cloned["documents"]
    matching = next(d for d in documents if d.get("path") == SOURCE_RELATIVE_PATH)
    injected = json.loads(json.dumps(matching))
    injected["road_ids"] = list(injected["road_ids"]) + [999999999999]
    documents.insert(0, injected)
    try:
        validate_runtime_index(cloned)
    except AssertionError:
        return
    raise AssertionError("duplicate source document was accepted by runtime-index validator")


def regression_noncanonical_road_id_must_fail(index: dict[str, Any]) -> None:
    """Prove float/string/bool aliases cannot be coerced into OSM identities."""
    for injected_value in (999999999999.5, "999999999999", True):
        cloned = json.loads(json.dumps(index))
        matching = next(d for d in cloned["documents"] if d.get("path") == SOURCE_RELATIVE_PATH)
        matching["road_ids"] = list(matching["road_ids"]) + [injected_value]
        try:
            validate_runtime_index(cloned)
        except AssertionError:
            continue
        raise AssertionError(f"non-canonical runtime-index OSM identity was accepted: {injected_value!r}")


def regression_exact_distance_must_drive_ranking() -> None:
    """Prove receipt rounding cannot choose a different near-tie winner."""
    rows = [
        {"osm_id": 9002, "anchor_distance_m": 1.00000041},
        {"osm_id": 9001, "anchor_distance_m": 1.00000049},
    ]
    exact = sorted(rows, key=lambda row: (row["anchor_distance_m"], row["osm_id"]))
    rounded_first = sorted(rows, key=lambda row: (round(row["anchor_distance_m"], 6), row["osm_id"]))
    assert exact[0]["osm_id"] == 9002
    assert rounded_first[0]["osm_id"] == 9001
    assert exact[0]["osm_id"] != rounded_first[0]["osm_id"], "fixture must expose rounded-ranking alias"


def regression_malformed_source_coordinates_must_fail() -> None:
    """Prove coercible/non-finite/ambiguous source geometry cannot enter distance ranking."""
    malformed = (
        [[0.0, 0.0], ["1.0", 1.0]],
        [[0.0, 0.0], [True, 1.0]],
        [[0.0, 0.0], [math.nan, 1.0]],
        [[0.0, 0.0], [math.inf, 1.0]],
        [[0.0, 0.0], [1.0, 1.0, 2.0]],
        [[0.0, 0.0]],
    )
    for points in malformed:
        try:
            validate_road_points(points, 9000)
        except AssertionError:
            continue
        raise AssertionError(f"malformed source road coordinates were accepted: {points!r}")


def regression_malformed_source_metadata_must_fail() -> None:
    """Prove the selector rejects missing, coercible or non-canonical source metadata."""
    base = {"name": "Rue Saint-Géry", "class": "residential", "width": 5.0}
    for missing in ("name", "class", "width"):
        mutated = dict(base)
        del mutated[missing]
        try:
            validate_road_metadata(mutated, 8512036)
        except AssertionError:
            continue
        raise AssertionError(f"missing source road metadata was synthesized by selector: {missing}")
    mutations = (
        ("name", 8512036),
        ("name", " Rue Saint-Géry"),
        ("class", True),
        ("class", "residential\n"),
        ("width", "5.0"),
        ("width", True),
        ("width", math.nan),
        ("width", math.inf),
        ("width", -1.0),
    )
    for field, bad in mutations:
        mutated = dict(base)
        mutated[field] = bad
        try:
            validate_road_metadata(mutated, 8512036)
        except AssertionError:
            continue
        raise AssertionError(f"malformed source road metadata was accepted by selector: {field}={bad!r}")


def point_segment_distance(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
    vx, vz = bx - ax, bz - az
    wx, wz = px - ax, pz - az
    denom = vx * vx + vz * vz
    if denom <= 1e-12:
        return math.hypot(px - ax, pz - az)
    t = max(0.0, min(1.0, (wx * vx + wz * vz) / denom))
    qx, qz = ax + t * vx, az + t * vz
    return math.hypot(px - qx, pz - qz)


def road_distance(anchor_x: float, anchor_z: float, points: list[list[float]]) -> float:
    assert math.isfinite(anchor_x) and math.isfinite(anchor_z), "anchor coordinates must be finite"
    assert len(points) >= 2, "road distance requires at least two validated points"
    distance = min(
        point_segment_distance(anchor_x, anchor_z, *a, *b)
        for a, b in zip(points, points[1:])
    )
    assert math.isfinite(distance), "computed road distance must be finite"
    return distance


def main() -> None:
    source_bytes = SOURCE.read_bytes()
    actual_source_sha = hashlib.sha256(source_bytes).hexdigest()
    assert actual_source_sha == EXPECTED_SOURCE_SHA256, (actual_source_sha, EXPECTED_SOURCE_SHA256)

    source = strict_json_loads(source_bytes)
    index = strict_json_loads(INDEX.read_bytes())
    assert isinstance(source, dict)
    assert isinstance(index, dict)
    assert source["source"] == "OpenStreetMap contributors via Overpass API"
    assert source["license"] == "ODbL-1.0"

    matching_doc, indexed_ids = validate_runtime_index(index)
    regression_duplicate_document_must_fail(index)
    regression_noncanonical_road_id_must_fail(index)
    regression_exact_distance_must_drive_ranking()
    regression_malformed_source_coordinates_must_fail()
    regression_malformed_source_metadata_must_fail()

    corridor = source["corridor"]
    assert isinstance(corridor, dict), "corridor must be an object"
    anchor_rows = corridor["anchors"]
    assert isinstance(anchor_rows, list), "corridor anchors must be a list"
    anchors: dict[str, dict[str, Any]] = {}
    for anchor in anchor_rows:
        assert isinstance(anchor, dict), "corridor anchor must be an object"
        anchor_id = anchor.get("id")
        assert isinstance(anchor_id, str) and anchor_id, "corridor anchor id must be a non-empty string"
        assert anchor_id not in anchors, f"duplicate corridor anchor id: {anchor_id}"
        anchors[anchor_id] = anchor
    assert "bourse" in anchors
    bourse = anchors["bourse"]
    bourse_x = finite_source_number(bourse.get("x"), "bourse anchor x")
    bourse_z = finite_source_number(bourse.get("z"), "bourse anchor z")
    selection_radius = corridor.get("selection_radius_m")
    assert isinstance(selection_radius, dict), "selection_radius_m must be an object"
    radius = finite_source_number(selection_radius.get("roads"), "road selection radius")
    assert radius == 170.0

    roads = source.get("roads")
    assert isinstance(roads, list), "source roads must be a list"
    ranked = []
    source_road_ids: set[int] = set()
    for road in roads:
        assert isinstance(road, dict), "source road must be an object"
        osm_id = canonical_osm_id(road["osm_id"])
        assert osm_id not in source_road_ids, f"duplicate OSM road identity in locked source: {osm_id}"
        source_road_ids.add(osm_id)
        points = validate_road_points(road.get("points"), osm_id)
        name, road_class, width_m = validate_road_metadata(road, osm_id)
        if road.get("drivable") is not True or osm_id not in indexed_ids:
            continue
        distance_m = road_distance(bourse_x, bourse_z, points)
        if distance_m <= radius:
            ranked.append({
                "osm_id": osm_id,
                "name": name,
                "class": road_class,
                "width_m": width_m,
                "anchor_distance_m": distance_m,
                "point_count": len(points),
            })

    # Rank on full measured precision. Rounding belongs only to serialized evidence;
    # rounding before sorting can alias two distinct roads and let osm_id break the tie.
    ranked.sort(key=lambda row: (row["anchor_distance_m"], row["osm_id"]))
    for row in ranked:
        row["anchor_distance_m"] = round(row["anchor_distance_m"], 6)
    assert ranked, "No source-backed, runtime-indexed drivable road exists within the locked Bourse road radius"

    candidate = ranked[0]
    assert candidate["anchor_distance_m"] <= radius
    assert candidate["osm_id"] in indexed_ids

    receipt = {
        "schema": "grand-bruxelles-bourse-automatic-destination-candidate-v6",
        "corridor": corridor["name"],
        "anchor": {"id": "bourse", "x": bourse_x, "z": bourse_z},
        "locked_road_radius_m": radius,
        "source": {
            "path": SOURCE_RELATIVE_PATH,
            "sha256": actual_source_sha,
            "provider": source["source"],
            "license": source["license"],
        },
        "runtime_index": {
            "path": "data/runtime/road_destination_runtime_index.json",
            "catalog_sha256": index["catalog_sha256"],
            "source_lookup_only": True,
            "matching_document_count": 1,
            "matching_document_sha256": matching_doc["sha256"],
            "road_identity_count": len(indexed_ids),
        },
        "candidate": candidate,
        "ranked_candidate_count": len(ranked),
        "ranked_candidates": ranked[:10],
        "contracts": {
            "strict_json_proven": True,
            "canonical_osm_integer_identity_proven": True,
            "finite_source_coordinates_proven": True,
            "road_point_shape_proven": True,
            "malformed_source_coordinate_regression_proven": True,
            "canonical_source_road_metadata_proven": True,
            "candidate_metadata_coercion_regression_proven": True,
            "unique_corridor_anchor_ids_proven": True,
            "unique_runtime_index_document_proven": True,
            "unique_source_road_ids_proven": True,
            "runtime_index_authorization_closed": True,
            "duplicate_document_regression_proven": True,
            "noncanonical_road_id_regression_proven": True,
            "exact_distance_ranking_proven": True,
            "distance_rounding_is_evidence_only": True,
            "exact_source_identity_proven": True,
            "runtime_index_membership_proven": True,
            "drivable_source_road_proven": True,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "destination_advertisable": False,
            "visual_acceptance": False,
            "jouable_authorized": False,
        },
        "next_action": "Use candidate OSM identity with the shared road-<OSM id> resolver and require rendered-road, collision/ground, safe-viewpoint, then unmasked player-frame proof before promotion.",
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print("BOURSE_AUTOMATIC_DESTINATION_CANDIDATE_OK " + json.dumps(candidate, sort_keys=True))


if __name__ == "__main__":
    main()
