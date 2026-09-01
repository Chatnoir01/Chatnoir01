#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-dynamic-chain-decomposition.yml"
GLOBAL_PROBE = ROOT / "tools" / "godot_civ1_global_chain_diagnostic.gd"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert GLOBAL_PROBE.exists(), "global-chain Godot probe missing"
    assert WORKFLOW.exists(), "dynamic chain decomposition workflow missing"

    workflow = WORKFLOW.read_text(encoding="utf-8")
    for token in (
        "Grand Bruxelles CIV-1 Dynamic Chain Decomposition",
        "godot_civ1_global_chain_diagnostic.gd",
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "dynamic_parent_child_decomposition",
        "RightLowerLeg_to_RightFoot",
        "LeftLowerLeg_to_LeftFoot",
        "circular_phase_shift_samples",
        "parent_trajectory_phase_shift_samples",
        "relative_trajectory_phase_shift_samples",
        "final_foot_vertical_min_sample_index",
        "final_phase_delta_samples",
        "target_min_error_attribution",
        "source_min_error_attribution",
        "parent_hips_relative_error_m",
        "parent_to_foot_relative_error_m",
        "final_foot_error_m",
        "algebraic_closure_error_m",
        "right_trajectory_phase_aligned",
        "right_target_min_parent_error_dominant",
        "right_source_min_cancellation",
        "right_target_min_reinforcement",
        "left_control_final_aligned",
        "dynamic_decomposition_classification",
        "parent_amplitude_error_unmasked_at_target_min",
        "PHASE_DIVERGENCE_MATERIAL_SAMPLES = 12",
        "sample_count']==121",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(workflow, token)

    print("CIV1_DYNAMIC_CHAIN_DECOMPOSITION_CONTRACT_OK")


if __name__ == "__main__":
    main()
