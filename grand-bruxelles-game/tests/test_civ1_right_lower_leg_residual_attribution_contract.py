#!/usr/bin/env python3
from pathlib import Path

GAME_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = GAME_ROOT.parent
WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-civ1-right-lower-leg-residual-attribution.yml"
GLOBAL_PROBE = GAME_ROOT / "tools/godot_civ1_global_chain_diagnostic.gd"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert WORKFLOW.is_file(), "missing RightLowerLeg residual attribution workflow"
    assert GLOBAL_PROBE.is_file(), "missing global-chain diagnostic probe"
    w = WORKFLOW.read_text(encoding="utf-8")

    for token in (
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "RESIDUAL_INDICES = [84, 85, 86, 87, 88]",
        "source_hips_relative_origin",
        "target_hips_relative_origin",
        "right_upper_leg_parent_counterfactual",
        "right_lower_leg_relative_counterfactual",
        "right_upper_leg_trajectory_dominant",
        "right_upper_leg_offset_span_m",
        "threshold_was_modified",
        "diagnostic_only",
        "world_ground_assumed",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(w, token)

    forbidden = ("threshold_rescue", "camera_rescue", "runtime_authorized=true", "world_ground_assumed=true")
    for token in forbidden:
        assert token not in w.lower(), f"forbidden rescue/authority token: {token}"

    print("CIV1_RIGHT_LOWER_LEG_RESIDUAL_ATTRIBUTION_CONTRACT_OK")


if __name__ == "__main__":
    main()
