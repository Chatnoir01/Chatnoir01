#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "data/visual/grand_place_town_hall_dormer_visualization.json"
RUNTIME = ROOT / "game/scripts/grand_place_town_hall_dormer_runtime.gd"
DESCRIPTOR = ROOT / "data/runtime/modules/grand_place_town_hall_dormers.json"
EXPECTED_BASE = "bffe110b9212ace10e1d4847436b51542bd95ab0"
EXPECTED_POPULATION = [3, 4, 4, 5]


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
    require(int(sum(EXPECTED_POPULATION)) == 16, "expected population invariant drift")
    require("hipped" in str(source.get("morphology", "")).lower(), "hipped morphology missing")
    require(bool(source.get("staggered_rows", False)), "staggered rows missing")

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
    require(gate.get("resolution") == [1280, 720], "canonical gate resolution drift")
    require(int(gate.get("minimum_changed_pixels", 0)) >= 350, "pixel threshold weakened")
    require(int(gate.get("minimum_bbox_width_px", 0)) >= 50, "bbox width threshold weakened")
    require(int(gate.get("minimum_bbox_height_px", 0)) >= 25, "bbox height threshold weakened")

    require(RUNTIME.exists(), "runtime implementation missing (expected red before implementation)")
    runtime = RUNTIME.read_text(encoding="utf-8")
    for token in [
        "class_name GrandPlaceTownHallDormerRuntime",
        "SurfaceTool",
        "BrusselsSlateRoofMaterial",
        "BrusselsWhiteStoneMaterial",
        "BrusselsArchitecturalGlazingMaterial",
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

    print("GRAND_PLACE_TOWN_HALL_DORMERS_OK face=9369301 rows=4 dormers=16 morphology=hipped source=photo_fit_not_survey")


if __name__ == "__main__":
    main()
