#!/usr/bin/env python3
from pathlib import Path

BUILDER = Path("grand-bruxelles-game/game/scripts/osm_city_builder.gd")
CANONICAL_OWNER = 'generic_osm_surface_collision_runtime'


def fail(message: str) -> None:
    raise SystemExit(f"OSM_CITY_BUILDER_COLLISION_AUTHORITY_FAIL: {message}")


def main() -> None:
    text = BUILDER.read_text(encoding="utf-8")

    # The visual OSM builder may render source-backed road/sidewalk surfaces,
    # but collision authority belongs exclusively to the canonical runtime that
    # derives player-only support from those visible top surfaces. A second body
    # with the same owner causes duplicate-owner recovery, log churn, and can
    # make road readiness depend on scene-order rather than one authority.
    forbidden = {
        f'ROAD_SUPPORT_OWNER_ID := "{CANONICAL_OWNER}"': "builder declares the canonical collision owner",
        'func _road_support_body(': "builder creates a parallel road-support body",
        'body.set_meta(ROAD_SUPPORT_OSM_IDS_META': "builder publishes canonical road-support IDs",
        '_add_road_support_shape(': "builder creates parallel road collision shapes",
        'road_support.add_child(support_collision)': "builder attaches sidewalk collision to parallel owner",
    }
    found = [reason for token, reason in forbidden.items() if token in text]
    if found:
        fail("; ".join(found))

    if 'segment.use_collision = false' not in text:
        fail("rendered road CSG must remain collision-disabled")
    if 'pavement.use_collision = false' not in text:
        fail("rendered sidewalk CSG must remain collision-disabled")
    if 'ANNEESSENS_ANCHOR := Vector2(-288.863, -100.711)' not in text:
        fail("bounded Anneessens detail source anchor drifted")
    if 'point_2d.distance_to(ANNEESSENS_ANCHOR) <= anneessens_detail_radius_m' not in text:
        fail("bounded Anneessens detail coverage drifted")

    print("OSM_CITY_BUILDER_COLLISION_AUTHORITY_OK: visual builder owns no canonical road collision bodies")


if __name__ == "__main__":
    main()
