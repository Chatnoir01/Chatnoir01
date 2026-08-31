#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "grand-bruxelles-game/tools/godot_civ1_sprint_retarget_preflight.gd"
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-civ1-sprint-retarget-preflight.yml"
STATUS = ROOT / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"


def require(text: str, needle: str) -> None:
    assert needle in text, f"missing contract token: {needle}"


def main() -> None:
    assert PROBE.exists(), "retarget preflight probe missing"
    assert WORKFLOW.exists(), "retarget preflight workflow missing"
    probe = PROBE.read_text()
    workflow = WORKFLOW.read_text()
    status = STATUS.read_text()

    for token in (
        "grand-bruxelles-civ1-sprint-retarget-preflight-v1",
        "UAL1_Standard/Sprint",
        "SkeletonProfileHumanoid",
        "source_to_target_scale_ratio",
        "mapped_required_bones",
        "unmapped_required_bones",
        '"retarget_ready": false',
        '"grounding_verified": false',
        '"foot_slide_verified": false',
        '"visual_approval_claimed": false',
    ):
        require(probe, token)

    for token in (
        "Grand Bruxelles CIV-1 Sprint Retarget Preflight",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "strip_glb_animations.py",
        "retarget-preflight.json",
    ):
        require(workflow, token)

    require(status, '"source_package_present": false')
    require(status, '"runtime_package_present": false')
    require(status, '"mixamo_payload_allowed": false')
    print("CIV1_SPRINT_RETARGET_PREFLIGHT_CONTRACT_OK")


if __name__ == "__main__":
    main()
