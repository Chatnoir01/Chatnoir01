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
        "parent_hips_relative_vertical_min_sample_index",
        "parent_to_foot_relative_vertical_min_sample_index",
        "final_foot_vertical_min_sample_index",
        "parent_phase_delta_samples",
        "relative_phase_delta_samples",
        "final_phase_delta_samples",
        "right_parent_phase_aligned",
        "right_relative_term_materially_divergent",
        "left_control_aligned",
        "dynamic_decomposition_classification",
        "parent_aligned_relative_term_divergent",
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
