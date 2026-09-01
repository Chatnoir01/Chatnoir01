#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT.parent / ".github/workflows/grand-bruxelles-civ1-y-z-interaction-ab.yml"
Z_BUILDER = ROOT / "tools/build_civ1_upperleg_lowerleg_z_candidate.py"
Y_BUILDER = ROOT / "tools/build_civ1_right_foot_grounded_candidate.py"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert WORKFLOW.exists(), "missing Y/Z interaction workflow"
    workflow = WORKFLOW.read_text(encoding="utf-8")
    z_builder = Z_BUILDER.read_text(encoding="utf-8")
    y_builder = Y_BUILDER.read_text(encoding="utf-8")

    for token in (
        "Grand Bruxelles CIV-1 Y Z Interaction A-B",
        "baseline-native.json",
        "y-only.json",
        "z-only.json",
        "y-plus-z.json",
        "121",
        "0.10",
        "UAL1_Standard/Sprint",
        "interaction-classification.json",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(workflow, token)

    require(y_builder, "SELECTED_ALPHA = 0.75")
    require(z_builder, '"grand-bruxelles-civ1-right-foot-reference-ab-v2"')
    require(z_builder, '"grand-bruxelles-civ1-right-foot-reference-ab-v4"')
    require(z_builder, "upperleg_lowerleg_z_lengths_preserved")

    assert "runtime_authorized':False" in workflow or '"runtime_authorized":False' in workflow
    assert "visual_approval_claimed':False" in workflow or '"visual_approval_claimed":False' in workflow
    print("CIV1_Y_Z_INTERACTION_AB_CONTRACT_GREEN")


if __name__ == "__main__":
    main()
