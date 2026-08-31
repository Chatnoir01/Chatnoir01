from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools/godot_quaternius_ik_observation_probe.gd"
FRAME_PROBE = ROOT / "tools/godot_quaternius_frame_settled_pose_probe.gd"
WORKFLOW = ROOT.parent / ".github/workflows/grand-bruxelles-quaternius-ik-observation-context.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"QUATERNIUS_IK_OBSERVATION_CONTRACT_FAIL: {message}")


def main() -> None:
    probe = PROBE.read_text(encoding="utf-8")
    frame_probe = FRAME_PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    require("grand-bruxelles-quaternius-ik-observation-context-v4" in probe, "source-track diagnostic format not pinned")
    require("observation_id" in probe and "scene_path" in probe and "animation_player_path" in probe, "deterministic observation identity missing")
    require("rotation_track_interpolate" in probe and "position_track_interpolate" in probe, "raw leg-chain motion diagnostics missing")
    require("bilateral_chain_motion" in probe, "bilateral source-track motion proof missing")
    require("direct_track_pose_measurement" in probe and "_apply_animation_tracks_to_skeleton" in probe, "historical direct evaluator diagnostic missing")
    require("track_get_path" in probe and "get_concatenated_subnames" in probe, "direct evaluator does not resolve imported bone targets")

    require("grand-bruxelles-quaternius-frame-settled-pose-v1" in frame_probe, "frame-settled canonical pose probe missing")
    require("call_deferred(\"_run\")" in frame_probe and "await process_frame" in frame_probe, "canonical probe does not settle through real SceneTree frames")
    require("player.seek" in frame_probe and "player.advance(0.0)" in frame_probe, "canonical deterministic AnimationPlayer sampling missing")
    require("get_bone_pose_position" in frame_probe and "get_bone_pose_rotation" in frame_probe, "canonical local bone pose evidence missing")
    require("get_bone_global_pose" in frame_probe, "canonical global foot pose evidence missing")
    require("bilateral_local_pose_motion" in frame_probe and "bilateral_global_pose_motion" in frame_probe, "canonical local/global bilateral proof missing")
    require("SAMPLE_COUNT := 61" in frame_probe, "canonical sampling density drifted")
    require('"semantic_selection_allowed": false' in frame_probe, "diagnostic must not select run semantics")
    require('"civ1_retarget_authorized": false' in frame_probe, "diagnostic must not authorize retarget")
    require('"grounding_verified": false' in frame_probe and '"foot_slide_verified": false' in frame_probe, "source pose diagnostic must not claim target grounding")

    require("5c4dae72e49ad4e5959571e00a25d3d872cacba5.zip" in workflow, "source archive is not commit pinned")
    require("f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767" in workflow, "source archive digest is not pinned")
    require("Godot_v4.7.1-stable_linux.x86_64.zip" in workflow, "Godot 4.7.1 is not pinned")
    require("gb_frame_settled_pose_probe.gd" in workflow and "frame-settled-pose.json" in workflow, "observation gate does not consume canonical frame-settled pose proof")
    require("bilateral_local_pose_motion" in workflow and "bilateral_global_pose_motion" in workflow, "workflow does not validate canonical bilateral pose motion")
    require("minimum_applied_track_count" in workflow, "workflow stopped checking imported track resolution evidence")
    require("semantic_selection_allowed" in workflow and "False" in workflow, "workflow must remain fail-closed")
    require("actions/upload-artifact@v4" in workflow and "if: always()" in workflow, "RED diagnostics must be retained")
    print("QUATERNIUS_IK_OBSERVATION_CONTRACT_OK: frame_settled_pose=canonical_fail_closed")


if __name__ == "__main__":
    main()
