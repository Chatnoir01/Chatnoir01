from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools" / "build_civ1_upperleg_lowerleg_z_candidate.py"
NORMALIZED = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-normalized-native-retarget.yml"
GROUNDING = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-grounding-readiness.yml"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert BUILDER.exists(), "missing Z-only candidate builder"
    builder = BUILDER.read_text(encoding="utf-8")
    normalized = NORMALIZED.read_text(encoding="utf-8")
    grounding = GROUNDING.read_text(encoding="utf-8")

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

    for workflow in (normalized, grounding):
        require(workflow, "build_civ1_upperleg_lowerleg_z_candidate.py")
        require(workflow, "CIV1_UPPERLEG_LOWERLEG_Z_CANDIDATE_BUILT")
        require(workflow, "upperleg_lowerleg_z_candidate_applied")
        require(workflow, "upperleg_lowerleg_z_lengths_preserved")

    print("CIV1_UPPERLEG_LOWERLEG_Z_CANDIDATE_CONTRACT_OK")


if __name__ == "__main__":
    main()
