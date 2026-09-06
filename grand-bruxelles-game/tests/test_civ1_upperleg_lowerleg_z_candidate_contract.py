from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools" / "build_civ1_upperleg_lowerleg_z_candidate.py"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-upperleg-lowerleg-z-candidate.yml"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert BUILDER.exists(), "missing Z-only candidate builder"
    assert WORKFLOW.exists(), "missing Z-only candidate workflow"
    builder = BUILDER.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    for token in (
        "axis-z UpperLeg->LowerLeg",
        "source_rest_in_target_parent_basis",
        "candidate.z = source_rest_in_target_parent_basis.z",
        "candidate = candidate.normalized() * target_length",
        "target_skeleton.set_bone_rest(target_child_idx, candidate_rest)",
        "target_skeleton.reset_bone_pose(target_child_idx)",
        "upperleg_lowerleg_z_candidate_applied",
        "upperleg_lowerleg_z_lengths_preserved",
        "CIV1_UPPERLEG_LOWERLEG_Z_CANDIDATE_BUILT",
    ):
        require(builder, token)

    for token in (
        "build_civ1_right_foot_grounded_candidate.py",
        "build_civ1_upperleg_lowerleg_z_candidate.py",
        "CIV1_UPPERLEG_LOWERLEG_Z_CANDIDATE_BUILT",
        "upperleg_lowerleg_z_candidate_applied",
        "upperleg_lowerleg_z_lengths_preserved",
        "strict_bilateral_improvement",
        "grounding_readiness_pass",
        "assert strict_bilateral_improvement is True",
        "assert grounding_readiness_pass is True",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
    ):
        require(workflow, token)

    print("CIV1_UPPERLEG_LOWERLEG_Z_CANDIDATE_CONTRACT_OK")


if __name__ == "__main__":
    main()
