#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT / "game/scripts/osm_city_builder.gd"
SURFACE_RUNTIME = ROOT / "game/scripts/brussels_osm_sidewalk_surface_runtime.gd"
EDGE_RUNTIME = ROOT / "game/scripts/brussels_sidewalk_edge_runtime.gd"
MODULE = ROOT / "data/runtime/modules/brussels_sidewalk_edge.json"
EXPECTED_MODULE_SCHEMA = "grand-bruxelles-runtime-module-v1"
EXPECTED_NAME = "BrusselsSidewalkEdgeRuntime"
EXPECTED_PATH = "res://game/scripts/brussels_sidewalk_edge_runtime.gd"

def fail(message: str) -> None:
    print(f"BRUSSELS_SIDEWALK_EDGE_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

def main() -> None:
    for path in (BUILDER, SURFACE_RUNTIME):
        if not path.is_file():
            fail(f"required production file missing: {path.relative_to(ROOT)}")
    builder = BUILDER.read_text(encoding="utf-8")
    surface = SURFACE_RUNTIME.read_text(encoding="utf-8")
    if "pavement.size = Vector3(sidewalk_width, 0.12, length)" not in builder:
        fail("existing authored 0.12 m sidewalk slab contract changed")
    if "pavement.position = center + perpendicular * offset * side + Vector3(0, 0.085, 0)" not in builder:
        fail("existing sidewalk placement contract changed")
    if "const EXPECTED_WIDTHS := [1.85, 2.55]" not in surface:
        fail("shared sidewalk width classifier changed")
    if "geometry_changed_by_sidewalk_surface_runtime\", false" not in surface:
        fail("sidewalk surface no-geometry-change invariant missing")
    if not EDGE_RUNTIME.is_file():
        fail("shared sidewalk edge runtime missing")
    if not MODULE.is_file():
        fail("sidewalk edge runtime registry descriptor missing")
    descriptor = json.loads(MODULE.read_text(encoding="utf-8"))
    if descriptor.get("schema") != EXPECTED_MODULE_SCHEMA:
        fail("module descriptor schema mismatch")
    if descriptor.get("enabled") is not True:
        fail("sidewalk edge module is not enabled")
    if descriptor.get("name") != EXPECTED_NAME or descriptor.get("path") != EXPECTED_PATH:
        fail("sidewalk edge module descriptor identity/path mismatch")
    runtime = EDGE_RUNTIME.read_text(encoding="utf-8")
    for token in ['MATERIAL_FAMILY := "brussels_sidewalk_edge_v1"','placement_provenance','authored_presentation_from_existing_sidewalk_geometry','source_height_claimed','false','geometry_unchanged()','edge_count()','set_enhanced_enabled','get_tree().root.find_child("GeneratedRoads"']:
        if token not in runtime:
            fail(f"runtime contract token missing: {token}")
    lowered = runtime.lower()
    for pattern in [r"source[_ -]?measured[_ -]?curb[_ -]?height",r"official[_ -]?curb[_ -]?height",r"osm[_ -]?curb[_ -]?height"]:
        if re.search(pattern, lowered):
            fail(f"unsupported source-height claim found: {pattern}")
    print("BRUSSELS_SIDEWALK_EDGE_OK: registry-backed presentation-only edge contract present; sidewalk geometry remains authoritative runtime input")

if __name__ == "__main__":
    main()
