#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROBE = ROOT / "grand-bruxelles-game/tools/godot_civ1_sprint_pose_transfer.gd"
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-civ1-sprint-pose-transfer.yml"
STATUS = ROOT / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"


def require(text: str, needle: str) -> None:
    assert needle in text, f"missing contract token: {needle}"


def main() -> None:
    assert PROBE.exists(), "Sprint pose-transfer probe missing"
    assert WORKFLOW.exists(), "Sprint pose-transfer workflow missing"
    probe = PROBE.read_text()
    workflow = WORKFLOW.read_text()
    status = STATUS.read_text()

    for token in (
        "grand-bruxelles-civ1-sprint-pose-transfer-v1",
        "UAL1_Standard/Sprint",
        "rest_normalized_global_delta",
        "source_to_target_scale_ratio",
        "target_left_foot_range_m",
        "target_right_foot_range_m",
        '"animation_transferred": transfer_ok',
        '"world_ground_assumed": false',
        '"grounding_verified": false',
        '"foot_slide_verified": false',
        '"visual_approval_claimed": false',
    ):
        require(probe, token)

    for token in (
        "Grand Bruxelles CIV-1 Sprint Pose Transfer",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "pose-transfer.json",
        "assert p['animation_transferred'] is True",
        "target_left_foot_range_m",
        "target_right_foot_range_m",
    ):
        require(workflow, token)

    require(status, '"production_authorized": false')
    require(status, '"runtime_package_present": false')
    require(status, '"mixamo_payload_allowed": false')
    print("CIV1_SPRINT_POSE_TRANSFER_CONTRACT_OK")


if __name__ == "__main__":
    main()
