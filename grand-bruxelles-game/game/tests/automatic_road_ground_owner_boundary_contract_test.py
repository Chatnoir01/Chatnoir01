#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOLVER = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"
BUILDER = ROOT / "game" / "scripts" / "osm_city_builder.gd"

resolver = RESOLVER.read_text(encoding="utf-8")
builder = BUILDER.read_text(encoding="utf-8")

resolver_required = [
    'const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"',
    'const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"',
    'func _ground_hit_is_authorized(collider: Object, canonical_ground: Node, osm_id: int = 0) -> bool:',
    'return osm_id <= 0',
    'return _road_support_contains_osm_id(node, osm_id)',
]
for needle in resolver_required:
    if needle not in resolver:
        raise SystemExit(f"AUTOMATIC_ROAD_GROUND_OWNER_BOUNDARY_RED: missing fail-closed resolver contract: {needle}")

if 'if canonical_ground != null and collider == canonical_ground:\n        return true' in resolver:
    raise SystemExit("AUTOMATIC_ROAD_GROUND_OWNER_BOUNDARY_RED: road-<OSM id> may still fall back to generic Ground")

# The OSM city builder is visual/source geometry only. Canonical road-owned
# collision is materialized by the runtime recovery path and validated by the
# exact-head Godot witnesses. Duplicating that authority here makes readiness
# depend on scene order and lets duplicate owners get discarded nondeterministically.
builder_required = [
    'segment.use_collision = false',
    'pavement.use_collision = false',
    '_add_sidewalks(root, start, finish, width, road_class)',
]
for needle in builder_required:
    if needle not in builder:
        raise SystemExit(f"AUTOMATIC_ROAD_GROUND_OWNER_BOUNDARY_RED: missing visual source-surface contract: {needle}")

builder_forbidden = [
    'ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"',
    'func _road_support_body(',
    'body.set_meta(ROAD_SUPPORT_OSM_IDS_META',
    'func _add_road_support_shape(',
    'road_support.add_child(support_collision)',
]
for needle in builder_forbidden:
    if needle in builder:
        raise SystemExit(f"AUTOMATIC_ROAD_GROUND_OWNER_BOUNDARY_RED: visual builder duplicates canonical collision authority: {needle}")

if 'segment.use_collision = true' in builder or 'pavement.use_collision = true' in builder:
    raise SystemExit("AUTOMATIC_ROAD_GROUND_OWNER_BOUNDARY_RED: visual CSG collision must not become an unowned bypass")

print(
    "AUTOMATIC_ROAD_GROUND_OWNER_BOUNDARY_GREEN: generic Ground is legacy-only; "
    "positive road IDs require exact canonical road-owned collision while visual OSM surfaces remain non-authoritative"
)
