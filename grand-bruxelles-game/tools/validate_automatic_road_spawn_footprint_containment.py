#!/usr/bin/env python3
"""Fail-closed contract for automatic road direct-entry support containment.

The deterministic first lateral candidate is half_road + 1.10 m. In corridor
OSM detail zones that point is on the rendered sidewalk, not on the carriageway.
The visual builder must stay non-authoritative for collision; positive road
spawns are accepted only through the canonical exact-owner/exact-OSM runtime
collision handshake.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game/scripts/automatic_road_direct_spawn.gd"
BUILDER = ROOT / "game/scripts/osm_city_builder.gd"


def fail(message: str) -> None:
    raise SystemExit(f"AUTOMATIC_ROAD_SPAWN_FOOTPRINT_CONTAINMENT_FAIL: {message}")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        fail(f"missing {label}: {needle}")


def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        fail(f"forbidden {label}: {needle}")


def main() -> None:
    runtime = RUNTIME.read_text(encoding="utf-8")
    builder = BUILDER.read_text(encoding="utf-8")

    # Candidate geometry must stay tied to the same rendered-road width used by
    # the source-backed OSM builder. Do not rescue containment by moving spawn.
    require(runtime, "var half_road := _display_road_width(road) * 0.5", "rendered road-width derivation")
    require(runtime, "half_road + 1.10", "deterministic first lateral candidate")
    require(runtime, "_ground_y(body, spawn_xz, osm_id)", "exact requested-road grounding")

    # Positive road IDs must prove the canonical collision owner and the exact
    # requested OSM id. Global Ground remains legacy/no-road only.
    require(runtime, 'const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"', "canonical collision owner")
    require(runtime, 'const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"', "canonical road-id metadata")
    require(runtime, 'str(node.get_meta(ROAD_SUPPORT_OWNER_META, "")) != ROAD_SUPPORT_OWNER_ID', "exact collision-owner check")
    require(runtime, "return _road_support_contains_osm_id(node, osm_id)", "exact requested-road membership")
    require(runtime, "return osm_id <= 0", "positive-road generic Ground rejection")

    # The visible support surface is the shared sidewalk geometry. Collision is
    # intentionally not authored here; a parallel builder-owned body would
    # duplicate the canonical runtime authority and reintroduce scene-order
    # dependence / duplicate-owned-support recovery.
    require(builder, 'var sidewalk_width := 2.55 if road_class in ["primary", "secondary"] else 1.85', "rendered sidewalk width")
    require(builder, "var offset := road_width * 0.5 + sidewalk_width * 0.5 + 0.10", "rendered sidewalk center")
    require(builder, "pavement.size = Vector3(sidewalk_width, 0.12, length)", "rendered sidewalk shape")
    require(builder, "pavement.position = center + perpendicular * offset * side + Vector3(0, 0.085, 0)", "rendered sidewalk transform")
    require(builder, "segment.use_collision = false", "non-authoritative rendered road")
    require(builder, "pavement.use_collision = false", "non-authoritative rendered sidewalk")

    for needle, label in {
        'ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"': "builder canonical-owner declaration",
        "func _road_support_body(": "parallel builder support body",
        "body.set_meta(ROAD_SUPPORT_OSM_IDS_META": "parallel builder road-id publication",
        "func _add_road_support_shape(": "parallel builder road collision",
        "support_shape.size = pavement.size": "parallel builder sidewalk collision shape",
        "support_collision.position = pavement.position": "parallel builder sidewalk collision transform",
        "road_support.add_child(support_collision)": "parallel builder sidewalk collision attachment",
    }.items():
        forbid(builder, needle, label)

    # The first source-safe lateral candidate is 1.10 m beyond the road edge.
    # Both sidewalk families start at +0.10 m and extend to at least +1.95 m,
    # so that candidate is strictly inside visible pavement, with 0.85 m min
    # outer clearance on the narrower local-road sidewalk.
    local_outer = 0.10 + 1.85
    major_outer = 0.10 + 2.55
    candidate = 1.10
    if not (0.10 < candidate < local_outer and 0.10 < candidate < major_outer):
        fail("first lateral candidate is not inside both rendered sidewalk families")

    print(
        "AUTOMATIC_ROAD_SPAWN_FOOTPRINT_CONTAINMENT_OK: "
        "first_candidate=half_road+1.10 visible_sidewalk_supported=true "
        "visual_builder_collision_authority=false canonical_runtime_owner_required=true "
        "exact_requested_osm_id_required=true global_ground_positive_road=false"
    )


if __name__ == "__main__":
    main()
