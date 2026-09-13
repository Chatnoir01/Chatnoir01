#!/usr/bin/env python3
from pathlib import Path

GAME_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = GAME_ROOT.parent
WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-civ1-right-foot-y-blend-sweep.yml"
BUILDER = GAME_ROOT / "tools/build_civ1_right_foot_y_blend_candidate.py"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert WORKFLOW.is_file(), "missing Y-blend sweep workflow"
    assert BUILDER.is_file(), "missing Y-blend candidate builder"
    w = WORKFLOW.read_text(encoding="utf-8")
    b = BUILDER.read_text(encoding="utf-8")

    for token in (
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "0.00 0.25 0.50 0.75 1.00",
        "manual_baseline_right_median_mps = 6.812484",
        "manual_baseline_right_p90_mps = 36.403685",
        "sample_count']==121",
        "strict_bilateral_improvement",
        "phase_overlap_improved",
        "primary_center_improved",
        "plane_error_improves_over_full",
        "eligible_nonzero",
        "residual_window",
        "parent_source_counterfactual",
        "relative_source_counterfactual",
        "unchanged_candidate_threshold_y",
        "residual_attribution",
        "diagnostic_only",
        "world_ground_assumed",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(w, token)

    for token in (
        "source_global_reference_direction_y_blend_preserve_target_length",
        "blend_alpha",
        "full_y",
        "original_y",
        "horizontal_length",
        "target_right_foot_length_preserved",
        "target_right_foot_y_blend_alpha",
    ):
        require(b, token)

    forbidden = ("threshold_rescue", "camera_rescue", "runtime_authorized=true", "world_ground_assumed=true")
    for token in forbidden:
        assert token not in w.lower(), f"forbidden rescue/authority token: {token}"

    print("CIV1_RIGHT_FOOT_Y_BLEND_SWEEP_CONTRACT_OK")


if __name__ == "__main__":
    main()
