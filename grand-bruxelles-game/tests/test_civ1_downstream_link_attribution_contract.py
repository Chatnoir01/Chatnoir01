#!/usr/bin/env python3
from pathlib import Path

GAME_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = GAME_ROOT.parent
WORKFLOW = REPO_ROOT / ".github/workflows/grand-bruxelles-civ1-downstream-link-attribution.yml"
GLOBAL_PROBE = GAME_ROOT / "tools/godot_civ1_global_chain_diagnostic.gd"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert WORKFLOW.is_file(), "missing downstream-link attribution workflow"
    assert GLOBAL_PROBE.is_file(), "missing global-chain diagnostic probe"
    w = WORKFLOW.read_text(encoding="utf-8")
    for token in (
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "RESIDUAL_INDICES = [84, 85, 86, 87, 88]",
        "RightUpperLeg",
        "LeftUpperLeg",
        "RightLowerLeg",
        "LeftLowerLeg",
        "RightFoot",
        "LeftFoot",
        "lowerleg_compensation_bilateral_delta_m",
        "foot_compensation_bilateral_delta_m",
        "downstream_link_classification",
        "lowerleg_relative_asymmetry_dominant",
        "foot_relative_asymmetry_dominant",
        "balanced_downstream_asymmetry",
        "threshold_was_modified",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(w, token)
    for token in ("threshold_rescue", "camera_rescue", "runtime_authorized=true", "world_ground_assumed=true"):
        assert token not in w.lower(), f"forbidden rescue/authority token: {token}"
    print("CIV1_DOWNSTREAM_LINK_ATTRIBUTION_CONTRACT_OK")


if __name__ == "__main__":
    main()
