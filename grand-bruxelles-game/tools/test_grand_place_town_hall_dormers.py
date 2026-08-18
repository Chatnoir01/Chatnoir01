#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "data/visual/grand_place_town_hall_dormer_visualization.json"
RUNTIME = ROOT / "game/scripts/grand_place_town_hall_dormer_runtime.gd"
DESCRIPTOR = ROOT / "data/runtime/modules/grand_place_town_hall_dormers.json"
EXPECTED_BASE = "a9dfd4f175f89587856899f15bf87ddeac7bf2ee"
EXPECTED_POPULATION = [3, 4, 4, 5]
EXPECTED_PHOTO_SHA = {
    "commons_michielverbeek_2015": "1bd1eff924d3b1a9b21ec83a63693d83f689aff06d47acea975095c9915178b1",
    "commons_zairon_2016": "c8d4123381926ed0473f08d82e54110c572d52a32e10b21d6fd90efb69658be8",
    "commons_emdee_2011": "339bec2eec75ee8e95ead893f532dc229008d6a66f3a6850f5c4fda93621854c",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"GRAND_PLACE_TOWN_HALL_DORMERS_FAIL: {message}")


def main() -> None:
    require(CONTRACT.exists(), "visualization contract missing")
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    require(contract.get("schema") == "grand-bruxelles-town-hall-dormer-visualization-v1", "schema drift")
    require(contract.get("production_base") == EXPECTED_BASE, "production base drift")
    target = contract.get("target", {})
    require(str(target.get("roof_face_id", "")).endswith("/9369301"), "wrong UrbIS roof face")
    require(abs(float(target.get("eave_span_m", 0.0)) - 15.9440934873) < 0.0001, "gallery eave span drift")

    source = contract.get("source_alignment", {})
    require(source.get("visible_population_top_to_bottom") == EXPECTED_POPULATION, "visible row population drift")
    require(sum(EXPECTED_POPULATION) == 16, "expected population invariant drift")
    require("hipped" in str(source.get("morphology", "")).lower(), "hipped morphology missing")
    require(bool(source.get("staggered_rows", False)), "staggered rows missing")
    require(source.get("visible_population_is_total_inventory_claim") is False, "visible pattern promoted to inventory claim")
    heritage = source.get("heritage_record", {})
    require(str(heritage.get("record_id", "")) == "31125", "heritage record drift")
    require(heritage.get("supports_exact_positions") is False and heritage.get("supports_exact_dimensions") is False, "heritage source over-claim")
    photos = source.get("photo_sources", [])
    require(len(photos) == 3, "photo source count drift")
    for photo in photos:
        photo_id = str(photo.get("id", ""))
        require(photo_id in EXPECTED_PHOTO_SHA, f"unknown photo source: {photo_id}")
        require(photo.get("sha256") == EXPECTED_PHOTO_SHA[photo_id], f"photo SHA drift: {photo_id}")
        require(photo.get("license") == "CC BY-SA 4.0", f"photo license drift: {photo_id}")

    convention = contract.get("visualization_convention", {})
    require(convention.get("placement_source") == "photo_fit_visualization_convention_not_survey_coordinates", "placement truth boundary drift")
    require(convention.get("dimensions_source") == "photo_fit_visualization_convention_not_survey_dimensions", "dimension truth boundary drift")
    rows = convention.get("row_u_fractions_top_to_bottom", [])
    require([len(row) for row in rows] == EXPECTED_POPULATION, "row layout drift")
    require(len(convention.get("row_slope_distance_from_eave_m_top_to_bottom", [])) == 4, "row slope layout drift")

    truth = contract.get("truth_boundary", {})
    for key in ["exact_3d_positions_resolved", "exact_dimensions_resolved", "photo_points_are_survey_coordinates", "urbis_mesh_modified"]:
        require(truth.get(key) is False, f"fail-closed truth boundary drift: {key}")
    require(truth.get("candidate_requires_visual_gate") is True, "visual gate must remain mandatory")

    gate = contract.get("predeclared_visual_gate", {})
    require([int(v) for v in gate.get("resolution", [])] == [1280, 720], "canonical gate resolution drift")
    require(int(gate.get("minimum_changed_pixels", 0)) >= 350, "pixel threshold weakened")
    require(int(gate.get("minimum_bbox_width_px", 0)) >= 50, "bbox width threshold weakened")
    require(int(gate.get("minimum_bbox_height_px", 0)) >= 25, "bbox height threshold weakened")

    require(RUNTIME.exists(), "runtime implementation missing")
    runtime = RUNTIME.read_text(encoding="utf-8")
    for token in [
        "class_name GrandPlaceTownHallDormerRuntime",
        "SurfaceTool",
        "brussels_slate_roof_material.gd",
        "brussels_white_stone_material.gd",
        "brussels_architectural_glazing_material.gd",
        "_add_hipped_dormer",
        "dormer_count",
        "photo_fit_visualization_convention_not_survey_coordinates",
        "9369301",
    ]:
        require(token in runtime, f"runtime semantic token missing: {token}")

    require(DESCRIPTOR.exists(), "runtime module descriptor missing")
    descriptor = json.loads(DESCRIPTOR.read_text(encoding="utf-8"))
    require(descriptor.get("schema") == "grand-bruxelles-runtime-module-v1", "descriptor schema drift")
    require(descriptor.get("enabled") is True, "descriptor disabled")
    require(descriptor.get("name") == "GrandPlaceTownHallDormerRuntime", "descriptor name drift")
    require(descriptor.get("path") == "res://game/scripts/grand_place_town_hall_dormer_runtime.gd", "descriptor path drift")

    print("GRAND_PLACE_TOWN_HALL_DORMERS_OK face=9369301 rows=4 dormers=16 morphology=hipped source=photo_fit_not_survey photos=3")


if __name__ == "__main__":
    main()
