from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools" / "godot_civ1_geometry_derived_placement_probe.gd"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-geometry-derived-placement.yml"


def require(text: str, needle: str) -> None:
    assert needle in text, f"missing contract token: {needle}"


def main() -> None:
    probe = PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    for token in [
        "const TARGET_SAMPLES := [68, 69, 70, 71]",
        "const REQUIRED_VERTEX_COUNT := 3306",
        "geometry_derived_placement_y_m",
        "placement_delta_m",
        "bilateral_lower_envelope_clearance_m",
        "geometry_lower_envelope_clearance_m",
        '"geometry_placement_is_runtime_solution":false',
        '"animation_correction_authorized":false',
        '"runtime_authorized":false',
        '"visual_approval_claimed":false',
        '"player_view_claimed":false',
        "posed_bone * inverse_bind * p_skeleton_rest",
    ]:
        require(probe, token)

    assert "percentile" not in probe.lower()
    assert "WEIGHT_THRESHOLD" not in probe
    assert "Camera3D" not in probe
    assert "viewport" not in probe.lower()

    for token in [
        "76183910ea9ffd2933f9e80c64c3a283f548aa47",
        "10031928117",
        "9996432028",
        "10024557192",
        "10037379556",
        "CIV1_GEOMETRY_PLACEMENT_OK",
        "fixed_vertex_count'] == 3306",
        "sample_indices'] == [68,69,70,71]",
        "geometry_placement_is_runtime_solution'] is False",
        "runtime_authorized'] is False",
    ]:
        require(workflow, token)

    print("CIV1_GEOMETRY_DERIVED_PLACEMENT_CONTRACT_OK")


if __name__ == "__main__":
    main()
