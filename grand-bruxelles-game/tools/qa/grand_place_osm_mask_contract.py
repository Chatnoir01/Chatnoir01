#!/usr/bin/env python3
from pathlib import Path
import re

RUNTIME = Path(__file__).resolve().parents[2] / "game" / "scripts" / "grand_place_complete_contour_runtime.gd"


def fail(message: str) -> None:
    print(f"GRAND_PLACE_OSM_MASK_CONTRACT_FAIL: {message}")
    raise SystemExit(1)


def main() -> None:
    text = RUNTIME.read_text(encoding="utf-8")
    grow = re.search(r"^const\s+OSM_MASK_GROW_M\s*:=\s*([0-9.]+)\s*$", text, re.MULTILINE)
    if not grow:
        fail("OSM_MASK_GROW_M contract is missing")
    grow_m = float(grow.group(1))
    if grow_m != 0.0:
        fail(f"spatial-only replacement mask expands authoritative UrbIS bounds by {grow_m:.3f} m; expected 0.0 m fail-closed footprint")

    fn = re.search(
        r"func _mask_replaced_osm\(owner_id: String, bounds: Rect2, scene: Node\) -> void:(.*?)(?=\nfunc )",
        text,
        re.DOTALL,
    )
    if not fn:
        fail("_mask_replaced_osm implementation is missing")
    body = fn.group(1)
    if "bounds.grow(OSM_MASK_GROW_M)" not in body:
        fail("mask implementation no longer exposes the reviewed grow contract")
    if "has_point(Vector2(node.global_position.x, node.global_position.z))" not in body:
        fail("mask no longer checks the generated building anchor against the authoritative footprint")
    if "replaced_by_urbis_building" not in body:
        fail("replacement ownership metadata is missing")

    print("GRAND_PLACE_OSM_MASK_CONTRACT_GREEN: authoritative footprint grow=0.0m; nearby non-overlapping OSM anchors remain visible")


if __name__ == "__main__":
    main()
