#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT / "game/scripts/osm_city_builder.gd"
SURFACE_RUNTIME = ROOT / "game/scripts/brussels_osm_sidewalk_surface_runtime.gd"
EDGE_RUNTIME = ROOT / "game/scripts/brussels_sidewalk_edge_runtime.gd"
PROJECT = ROOT / "project.godot"


def fail(message: str) -> None:
    print(f"BRUSSELS_SIDEWALK_EDGE_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    for path in (BUILDER, SURFACE_RUNTIME, PROJECT):
        if not path.is_file():
            fail(f"required production file missing: {path.relative_to(ROOT)}")

    builder = BUILDER.read_text(encoding="utf-8")
    surface = SURFACE_RUNTIME.read_text(encoding="utf-8")
    project = PROJECT.read_text(encoding="utf-8")

    # Lock the existing authored geometry instead of inventing a new curb elevation.
    if "pavement.size = Vector3(sidewalk_width, 0.12, length)" not in builder:
        fail("existing authored 0.12 m sidewalk slab contract changed")
    if "pavement.position = center + perpendicular * offset * side + Vector3(0, 0.085, 0)" not in builder:
        fail("existing sidewalk placement contract changed")
    if "const EXPECTED_WIDTHS := [1.85, 2.55]" not in surface:
        fail("shared sidewalk width classifier changed")
    if "geometry_changed_by_sidewalk_surface_runtime\", false" not in surface:
        fail("sidewalk surface no-geometry-change invariant missing")

    if not EDGE_RUNTIME.is_file():
        fail("red-first witness: shared sidewalk edge runtime missing")

    runtime = EDGE_RUNTIME.read_text(encoding="utf-8")
    required_tokens = [
        'MATERIAL_FAMILY := "brussels_sidewalk_edge_v1"',
        'placement_provenance',
        'authored_presentation_from_existing_sidewalk_geometry',
        'source_height_claimed',
        'false',
        'geometry_unchanged()',
        'edge_count()',
        'set_enhanced_enabled',
    ]
    for token in required_tokens:
        if token not in runtime:
            fail(f"runtime contract token missing: {token}")

    if "BrusselsSidewalkEdgeRuntime=" not in project:
        fail("shared sidewalk edge runtime is not wired as an autoload")

    # Reject accidental geometry-source overclaim language in this narrow lot.
    forbidden = [
        r"source[_ -]?measured[_ -]?curb[_ -]?height",
        r"official[_ -]?curb[_ -]?height",
        r"OSM[_ -]?curb[_ -]?height",
    ]
    lowered = runtime.lower()
    for pattern in forbidden:
        if re.search(pattern.lower(), lowered):
            fail(f"unsupported source-height claim found: {pattern}")

    print("BRUSSELS_SIDEWALK_EDGE_OK: presentation-only edge contract present; sidewalk geometry remains authoritative runtime input")


if __name__ == "__main__":
    main()
