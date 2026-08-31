from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools/godot_quaternius_ik_observation_probe.gd"
WORKFLOW = ROOT.parent / ".github/workflows/grand-bruxelles-quaternius-ik-observation-context.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"QUATERNIUS_IK_OBSERVATION_CONTRACT_FAIL: {message}")


def main() -> None:
    probe = PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    require("grand-bruxelles-quaternius-ik-observation-context-v2" in probe, "pose-application probe format not pinned")
    require("observation_id" in probe and "scene_path" in probe and "animation_player_path" in probe, "deterministic observation identity missing")
    require("Master_Rigged.tscn" in probe and "reference_context_candidates" in probe, "reference context remains implicit")
    require("rotation_track_interpolate" in probe and "position_track_interpolate" in probe, "raw leg-chain motion diagnostics missing")
    require("leftfoot" in probe and "rightfoot" in probe and "leftleg" in probe and "rightleg" in probe, "bilateral leg chain is not pinned")
    require("bilateral_chain_motion" in probe, "bilateral motion proof missing")
    require("player.seek" in probe and "player.advance(0.0)" in probe and "force_update_bone_child_transform" in probe, "exact AnimationPlayer/Skeleton pose application path missing immediate mixer evaluation")
    require("get_bone_global_pose" in probe and "pose_samples" in probe, "bilateral sampled bone poses missing")
    require("left_foot_pose_range_m" in probe and "right_foot_pose_range_m" in probe, "bilateral foot pose motion metrics missing")
    require('"semantic_selection_allowed": false' in probe, "diagnostic must not select run semantics")
    require('"civ1_retarget_authorized": false' in probe, "diagnostic must not authorize retarget")
    require('"grounding_verified": false' in probe and '"foot_slide_verified": false' in probe, "pose diagnostic must not claim target grounding")
    require("5c4dae72e49ad4e5959571e00a25d3d872cacba5.zip" in workflow, "source archive is not commit pinned")
    require("f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767" in workflow, "source archive digest is not pinned")
    require("Godot_v4.7.1-stable_linux.x86_64.zip" in workflow, "Godot 4.7.1 is not pinned")
    require("reference_context_candidates" in workflow and "bilateral_chain_motion" in workflow, "workflow does not validate observation identity/motion")
    require("pose_samples" in workflow and "left_foot_pose_range_m" in workflow and "right_foot_pose_range_m" in workflow, "workflow does not validate applied foot poses")
    require("semantic_selection_allowed" in workflow and "False" in workflow, "workflow must remain fail-closed")
    require("actions/upload-artifact@v4" in workflow and "observation-context.json" in workflow, "diagnostic artifact is not preserved")
    require("if: always()" in workflow, "RED diagnostics must be retained")
    print("QUATERNIUS_IK_OBSERVATION_CONTRACT_OK: per_rig_pose_application=locked_fail_closed")


if __name__ == "__main__":
    main()
