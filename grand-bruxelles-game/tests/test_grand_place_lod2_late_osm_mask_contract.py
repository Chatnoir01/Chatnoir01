#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = [
    ROOT / "game/scripts/grand_place_official_lod2_1655673.gd",
    ROOT / "game/scripts/grand_place_official_lod2_1786758.gd",
]


def validate_script(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    assert 'get_node_or_null("BrusselsOSM/GeneratedBuildings")' in text
    assert "_mask_replaced_osm(source_bounds)" in text

    finite_startup_window = "for _frame: int in range(8):" in text
    has_late_node_watch = "node_added" in text or "child_entered_tree" in text
    has_post_build_retry = "_mask_replaced_osm_when_ready" in text or "_retry_osm_mask" in text

    assert not (
        finite_startup_window and not has_late_node_watch and not has_post_build_retry
    ), (
        f"{path.name}: official LoD2 replacement masking is limited to the first 8 frames; "
        "an OSM GeneratedBuildings mount arriving later can remain visible/collidable beside the UrbIS LoD2. "
        "Require an idempotent late-arrival watcher/retry owned by the Grand-Place runtime owner."
    )


if __name__ == "__main__":
    for script in SCRIPTS:
        validate_script(script)
    print("GRAND_PLACE_LOD2_LATE_OSM_MASK_OK scripts=2 geometry_mutated=false camera_mutated=false")
