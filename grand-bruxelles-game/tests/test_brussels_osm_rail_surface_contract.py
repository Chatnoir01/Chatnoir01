import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data/osm/vertical_slice_01.game.json"
BUILDER = ROOT / "game/scripts/osm_city_builder.gd"
MATERIAL = ROOT / "game/scripts/brussels_osm_rail_surface_material.gd"
RUNTIME = ROOT / "game/scripts/brussels_osm_rail_surface_runtime.gd"
PROJECT = ROOT / "project.godot"

# Locked before the first render. Never lower these to rescue the lot.
MIN_GT3_RATIO = 0.0050
MIN_GT8_RATIO = 0.0020
MIN_BBOX_WIDTH = 300
MIN_BBOX_HEIGHT = 70
MAX_ANCHOR_DISTANCE_M = 45.0

ANCHORS = {
    "midi": (-668.5, 627.84),
    "anneessens": (-272.04, -217.07),
    "bourse": (81.54, -664.58),
    "grand_place": (319.01, -535.2),
}


def point_segment_distance(point, start, finish):
    px, pz = point
    ax, az = start
    bx, bz = finish
    dx, dz = bx - ax, bz - az
    length2 = dx * dx + dz * dz
    if length2 <= 1e-12:
        return math.hypot(px - ax, pz - az)
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / length2))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def main():
    payload = json.loads(DATA.read_text(encoding="utf-8"))
    assert payload["source"] == "OpenStreetMap contributors via Overpass API"
    assert payload["license"] == "ODbL-1.0"
    railways = payload.get("railways", [])
    assert railways, "BRUSSELS_OSM_RAIL_SURFACE_FAIL: no source railways"

    visible_segments = []
    for railway in railways:
        if railway.get("surface_visible", True) is False:
            continue
        points = railway.get("points", [])
        for index in range(len(points) - 1):
            a, b = points[index], points[index + 1]
            if math.hypot(float(b[0]) - float(a[0]), float(b[1]) - float(a[1])) < 0.75:
                continue
            visible_segments.append((railway.get("osm_id"), index, a, b))

    assert visible_segments, "BRUSSELS_OSM_RAIL_SURFACE_FAIL: no renderable source rail segments"

    nearest = None
    for anchor_id, anchor in ANCHORS.items():
        for osm_id, index, a, b in visible_segments:
            distance = point_segment_distance(anchor, (float(a[0]), float(a[1])), (float(b[0]), float(b[1])))
            candidate = (distance, anchor_id, osm_id, index)
            if nearest is None or candidate < nearest:
                nearest = candidate

    assert nearest is not None
    print(
        "BRUSSELS_OSM_RAIL_SOURCE_AUDIT: "
        f"railways={len(railways)} renderable_segments={len(visible_segments)} "
        f"nearest_anchor={nearest[1]} nearest_m={nearest[0]:.3f} osm_id={nearest[2]} segment={nearest[3]} "
        f"visual_gate=gt3>={MIN_GT3_RATIO:.2%},gt8>={MIN_GT8_RATIO:.2%},bbox>={MIN_BBOX_WIDTH}x{MIN_BBOX_HEIGHT}"
    )
    assert nearest[0] <= MAX_ANCHOR_DISTANCE_M, (
        "BRUSSELS_OSM_RAIL_SURFACE_FAIL: no legitimate zone anchor is close enough for a normal-player rail witness "
        f"({nearest[0]:.3f} m > {MAX_ANCHOR_DISTANCE_M:.1f} m)"
    )

    builder = BUILDER.read_text(encoding="utf-8")
    assert 'rail.name = "Rail_%s_%d_%s"' in builder
    assert "rail.size = Vector3(0.095, 0.09, length)" in builder
    assert "rail.position =" in builder
    assert "rail.material = _rail_material" in builder

    # RED-first: fail until a reusable presentation-only material and the existing-geometry runtime exist.
    assert MATERIAL.exists(), "BRUSSELS_OSM_RAIL_SURFACE_RED: reusable rail surface material missing"
    assert RUNTIME.exists(), "BRUSSELS_OSM_RAIL_SURFACE_RED: existing-geometry rail surface runtime missing"

    material = MATERIAL.read_text(encoding="utf-8")
    runtime = RUNTIME.read_text(encoding="utf-8")
    project = PROJECT.read_text(encoding="utf-8")
    for token in (
        'brussels_osm_rail_surface_v1',
        'surface_composition_claimed", false',
        'exact_rgb_is_photometric_measurement", false',
        'wear_pattern_claimed", false',
        'geometry_changed", false',
        'ODbL-1.0',
    ):
        assert token in material, f"BRUSSELS_OSM_RAIL_SURFACE_FAIL missing material contract: {token}"
    assert 'name.begins_with("Rail_")' in runtime
    assert "set_enhanced_enabled" in runtime
    assert "BrusselsOsmRailSurfaceRuntime=" in project
    assert "brussels_osm_rail_surface_runtime.gd" in project
    print("BRUSSELS_OSM_RAIL_SURFACE_CONTRACT_OK")


if __name__ == "__main__":
    main()
