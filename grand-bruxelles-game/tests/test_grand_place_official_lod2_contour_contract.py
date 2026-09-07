#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "data/urbis/grand_place_lod2"
PROJECT = ROOT / "project.godot"
RUNTIME = ROOT / "game/scripts/grand_place_official_lod2_contour_runtime.gd"
DEDICATED = {"1655673", "1786758"}
PACKAGE_SHA256 = "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
DEGENERATE_AREA2_EPSILON = 1e-12
SUPPORTED_FACE_TYPES = {"WALLSURFACE", "ROOFSURFACE", "GROUNDSURFACE"}
EXPECTED_ZERO_SURFACE = {
    ("1601884", "https://databrussels.be/id/buildingface/10910246", 3),
    ("1608847", "https://databrussels.be/id/buildingface/10932426", 5),
    ("1608851", "https://databrussels.be/id/buildingface/10787507", 2),
    ("1611166", "https://databrussels.be/id/buildingface/10921163", 4),
    ("1611166", "https://databrussels.be/id/buildingface/10921409", 0),
    ("1613517", "https://databrussels.be/id/buildingface/10918081", 2),
    ("1613517", "https://databrussels.be/id/buildingface/10918083", 0),
    ("1635455", "https://databrussels.be/id/buildingface/10928302", 0),
    ("1645578", "https://databrussels.be/id/buildingface/10797637", 2),
}


def triangle_cross_length_sq(triangle: list[list[float]]) -> float:
    ax, ay, az = triangle[0]
    bx, by, bz = triangle[1]
    cx, cy, cz = triangle[2]
    ux, uy, uz = bx - ax, by - ay, bz - az
    vx, vy, vz = cx - ax, cy - ay, cz - az
    cross_x = uy * vz - uz * vy
    cross_y = uz * vx - ux * vz
    cross_z = ux * vy - uy * vx
    return cross_x * cross_x + cross_y * cross_y + cross_z * cross_z


def load_source_set() -> tuple[list[str], int, int, int, int, set[str]]:
    ids: list[str] = []
    faces = 0
    triangles = 0
    ground_triangles = 0
    observed_face_types: set[str] = set()
    observed_zero_surface: set[tuple[str, str, int]] = set()
    for path in sorted(SOURCE_DIR.glob("*.game.json")):
        building_id = path.name.removesuffix(".game.json")
        data = json.loads(path.read_text(encoding="utf-8"))
        source = data["source"]
        evidence = data["evidence"]
        assert data["schema"] == "grand-bruxelles-urbis-context-mesh-v1"
        assert source["building_2d_id"] == f"https://databrussels.be/id/building/{building_id}"
        assert source["crs"] == "EPSG:31370"
        assert source["license"] == "CC0-1.0"
        assert source["package_sha256"] == PACKAGE_SHA256
        assert data["runtime_approved"] is False
        assert int(evidence["face_count"]) == len(data["faces"])
        actual_triangles = sum(len(face.get("triangles", [])) for face in data["faces"])
        assert int(evidence["triangle_count"]) == actual_triangles, (
            f"{building_id}: evidence triangle_count={evidence['triangle_count']} but source contains {actual_triangles}"
        )
        source_face_type_counts = {
            str(face_type): int(count) for face_type, count in evidence.get("face_type_counts", {}).items()
        }
        actual_face_type_counts: dict[str, int] = {}
        for face_index, face in enumerate(data["faces"]):
            assert isinstance(face, dict), f"{building_id}: face {face_index} is not an object"
            face_id = str(face.get("id", ""))
            face_type = str(face.get("type", ""))
            assert face_type in SUPPORTED_FACE_TYPES, f"{building_id}: unsupported face type {face_type!r}"
            observed_face_types.add(face_type)
            actual_face_type_counts[face_type] = actual_face_type_counts.get(face_type, 0) + 1
            face_triangles = face.get("triangles", [])
            assert isinstance(face_triangles, list), f"{building_id}: malformed triangle list at face={face_index}"
            if face_type == "GROUNDSURFACE":
                ground_triangles += len(face_triangles)
            for triangle_index, triangle in enumerate(face_triangles):
                assert isinstance(triangle, list) and len(triangle) == 3, (
                    f"{building_id}: malformed triangle at face={face_index} triangle={triangle_index}"
                )
                for point_index, point in enumerate(triangle):
                    assert isinstance(point, list) and len(point) == 3, (
                        f"{building_id}: malformed point at face={face_index} triangle={triangle_index} point={point_index}"
                    )
                    assert all(isinstance(value, (int, float)) and math.isfinite(value) for value in point), (
                        f"{building_id}: non-finite/non-numeric point at face={face_index} triangle={triangle_index} point={point_index}"
                    )
                cross_length_sq = triangle_cross_length_sq(triangle)
                key = (building_id, face_id, triangle_index)
                if cross_length_sq <= DEGENERATE_AREA2_EPSILON:
                    assert face_type == "WALLSURFACE", f"unexpected zero-surface non-wall triangle: {key}"
                    assert key in EXPECTED_ZERO_SURFACE, f"unregistered zero-surface official triangle: {key}"
                    assert key not in observed_zero_surface, f"duplicate zero-surface official triangle identity: {key}"
                    observed_zero_surface.add(key)
                else:
                    assert key not in EXPECTED_ZERO_SURFACE, f"registered zero-surface triangle is no longer degenerate: {key}"
        assert actual_face_type_counts == source_face_type_counts, (
            f"{building_id}: evidence face_type_counts={source_face_type_counts} but source contains {actual_face_type_counts}"
        )
        faces += int(evidence["face_count"])
        triangles += int(evidence["triangle_count"])
        ids.append(building_id)
    assert observed_zero_surface == EXPECTED_ZERO_SURFACE, (
        f"zero-surface exclusion drift: expected={sorted(EXPECTED_ZERO_SURFACE)} observed={sorted(observed_zero_surface)}"
    )
    return ids, faces, triangles, len(observed_zero_surface), ground_triangles, observed_face_types


def main() -> None:
    ids, faces, triangles, excluded, ground_triangles, face_types = load_source_set()
    remaining = [building_id for building_id in ids if building_id not in DEDICATED]
    assert len(ids) == 25, f"expected 25 official Grand-Place owners, got {len(ids)}"
    assert faces == 715, f"official face total drifted: {faces}"
    assert triangles == 2170, f"official triangle total drifted: {triangles}"
    assert excluded == 9, f"expected exactly 9 proven zero-surface source records, got {excluded}"
    assert face_types == SUPPORTED_FACE_TYPES, f"official face-type set drifted: {sorted(face_types)}"
    assert ground_triangles > 0, "official source no longer exposes the proven ground-surface class"
    assert DEDICATED.issubset(ids)
    assert len(remaining) == 23, f"expected 23 non-dedicated owners, got {len(remaining)}"

    project = PROJECT.read_text(encoding="utf-8")
    mount = 'GrandPlaceOfficialLod2Contour="*res://game/scripts/grand_place_official_lod2_contour_runtime.gd"'
    assert project.count(mount) == 1, "23-owner official contour runtime is not mounted exactly once"
    assert RUNTIME.exists(), "23-owner official contour runtime is missing"
    runtime = RUNTIME.read_text(encoding="utf-8")
    for token in (
        "grand_place_lod2",
        "DEDICATED_OWNER_IDS",
        "EXPECTED_ZERO_SURFACE_TRIANGLES",
        "EPSG:31370",
        "CC0-1.0",
        PACKAGE_SHA256,
        "runtime_approved",
        "create_trimesh_collision",
        "node_added",
        "visual_acceptance",
        "jouable_authorized",
        "unregistered zero-surface triangle",
        "registered zero-surface triangle drifted",
        "source_zero_surface_triangle_count",
        "GROUNDSURFACE",
        "source_ground_surface_policy",
        "validated_source_not_mounted",
    ):
        assert token in runtime, f"runtime contour contract missing token: {token}"
    assert runtime.count("|https://databrussels.be/id/buildingface/") == 9, "runtime exclusion table must contain exactly nine provenance-bound zero-surface records"
    assert "get_tree().node_added.connect(_on_tree_node_added)" in runtime
    assert "get_tree().node_added.disconnect(_on_tree_node_added)" in runtime
    assert '_build_surface(owner_root, owner_id, faces, "GROUNDSURFACE"' not in runtime, (
        "official building GROUNDSURFACE must be validated for source integrity but not mounted over the separate plaza ground layer"
    )

    # Transactional-build regression: a source/build failure after some owners have
    # materialized must not leave partial official geometry or partially mask OSM.
    assert "func _reset_partial_build_state() -> void:" in runtime, "contour runtime must expose deterministic partial-build rollback"
    build = runtime[runtime.index("func _build_when_scene_ready() -> void:"):runtime.index("func _official_source_files()")]
    assert build.index("_reset_partial_build_state()") < build.index("_ensure_materials()"), "every build attempt must start from a clean contour state"
    assert build.count("_reset_partial_build_state()") >= 6, "all fail-closed exits after validation/build begins must rollback partial contour state"
    owner_build = runtime[runtime.index("func _build_owner("):runtime.index("func _point(")]
    assert "_mask_existing_osm_for_owner" not in owner_build, "OSM masking must not happen owner-by-owner before the full 23-owner contour is validated"
    assert build.index("_built = true") < build.index("_rescan_generated_buildings()"), "OSM masking may begin only after the complete contour is committed"

    mounted_source_triangles = triangles - ground_triangles - excluded
    print(
        "GRAND_PLACE_OFFICIAL_CONTOUR_CONTRACT_OK "
        f"owners=25 remaining=23 faces={faces} source_triangles={triangles} "
        f"ground_triangles_validated_not_mounted={ground_triangles} "
        f"explicit_zero_surface_exclusions={excluded} mounted_wall_roof_triangles={mounted_source_triangles} "
        "transactional_build=true source_mutated=false visual_acceptance=false jouable_authorized=false"
    )


if __name__ == "__main__":
    main()
