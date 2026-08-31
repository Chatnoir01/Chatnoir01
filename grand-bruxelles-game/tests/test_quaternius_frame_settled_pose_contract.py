from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools/godot_quaternius_frame_settled_pose_probe.gd"
WORKFLOW = ROOT.parent / ".github/workflows/grand-bruxelles-quaternius-frame-settled-pose.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"QUATERNIUS_FRAME_SETTLED_CONTRACT_FAIL: {message}")


def main() -> None:
    probe = PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    require("call_deferred(\"_run\")" in probe, "probe still executes body inside SceneTree _init")
    require("await process_frame" in probe, "real SceneTree frame settlement is missing")
    require("player.seek" in probe and "player.advance(0.0)" in probe, "deterministic AnimationPlayer sampling missing")
    require("get_bone_pose_position" in probe and "get_bone_pose_rotation" in probe, "local bone pose evidence missing")
    require("get_bone_global_pose" in probe, "global foot pose evidence missing")
    require("bilateral_local_pose_motion" in probe and "bilateral_global_pose_motion" in probe, "local/global motion split missing")
    require("SAMPLE_COUNT := 61" in probe, "sampling density drifted")
    require('"semantic_selection_allowed": false' in probe, "probe must not select run semantics")
    require('"civ1_retarget_authorized": false' in probe, "probe must not authorize CIV-1 retarget")
    require('"grounding_verified": false' in probe and '"foot_slide_verified": false' in probe, "source probe cannot claim target grounding")
    require("Godot_v4.7.1-stable_linux.x86_64.zip" in workflow, "Godot 4.7.1 not pinned")
    require("f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767" in workflow, "Quaternius archive digest not pinned")
    require("frame-settled-pose.json" in workflow and "if: always()" in workflow, "frame-settled RED evidence not preserved")
    print("QUATERNIUS_FRAME_SETTLED_CONTRACT_OK: process_frame_sampling=fail_closed")


if __name__ == "__main__":
    main()
