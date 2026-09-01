from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-civ1-grounding-readiness.yml"
BUILDER = ROOT / "grand-bruxelles-game/tools/build_civ1_right_foot_grounded_candidate.py"


def require(text: str, needle: str) -> None:
    assert needle in text, f"missing grounding contract token: {needle}"


def main() -> None:
    assert WORKFLOW.exists(), "grounding readiness workflow must exist"
    assert BUILDER.exists(), "selected Y-blend candidate builder must exist"
    text = WORKFLOW.read_text(encoding="utf-8")
    builder = BUILDER.read_text(encoding="utf-8")

    for token in (
        "SELECTED_ALPHA = 0.75",
        "source_global_reference_direction_y_blend_preserve_target_length",
        "target_right_foot_y_blend_alpha",
    ):
        require(builder, token)

    for token in (
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "Godot_v4.7.1-stable_linux.x86_64",
        "UAL1_Standard/Sprint",
        "SAMPLE_COUNT == 121",
        "SUPPORT_BAND_FRACTION == 0.10",
        "build_civ1_right_foot_grounded_candidate.py",
        "CIV1_RIGHT_FOOT_GROUNDED_CANDIDATE_BUILT alpha=0.75",
        "assert p['format']=='grand-bruxelles-civ1-right-foot-reference-ab-v4'",
        "assert abs(float(p['target_right_foot_y_blend_alpha'])-0.75) < 1e-9",
    ):
        require(text, token)

    for token in (
        "source_relative_plane_error_m",
        "normalized_plane_error_m",
        "baseline_plane_error_m",
        "median_horizontal_speed_mps",
        "p90_horizontal_speed_mps",
        "low_height_windows",
        "source_parity_no_foot_slide",
        "no_secondary_support_window",
        "grounding_readiness_pass",
    ):
        require(text, token)

    for token in (
        "assert p['diagnostic_only'] is True",
        "assert p['world_ground_assumed'] is False",
        "assert p['grounding_verified'] is False",
        "assert p['foot_slide_verified'] is False",
        "assert p['runtime_authorized'] is False",
        "assert p['visual_approval_claimed'] is False",
        "assert grounding_readiness_pass is True",
    ):
        require(text, token)

    require(text, "windows are measured, never discarded")
    print("civ1 grounding readiness contract OK")


if __name__ == "__main__":
    main()
