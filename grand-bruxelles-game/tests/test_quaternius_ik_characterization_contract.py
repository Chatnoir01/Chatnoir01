from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "tools/godot_quaternius_ik_probe.gd"
WORKFLOW = ROOT.parent / ".github/workflows/grand-bruxelles-quaternius-ik-characterization.yml"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"QUATERNIUS_IK_CHARACTERIZATION_CONTRACT_FAIL: {message}")


def main() -> None:
    probe = PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")
    require("grand-bruxelles-quaternius-ik-godot-characterization-v4" in probe, "probe format is not pinned to v4")
    require("Skeleton3D" in probe and "AnimationPlayer" in probe, "probe must inspect skeletons and animation players")
    require("skinned_mesh_count" in probe and "bone_names" in probe and "animation_names" in probe, "probe metrics incomplete")
    require("animation_metrics" in probe and "length_seconds" in probe and "loop_mode" in probe and "track_count" in probe, "locomotion semantic metrics missing")
    require("animation_metric_conflicts" in probe, "duplicate animation metric conflict detection missing")
    require("kinematic_metrics" in probe, "candidate kinematic metrics missing")
    require("KINEMATIC_SAMPLE_COUNT" in probe, "kinematic sampling cadence is not pinned")
    require("track_get_path" in probe and "TYPE_POSITION_3D" in probe and "position_track_interpolate" in probe, "position-track kinematic sampling missing")
    require("UAL1_Standard/Jog_Fwd" in probe and "UAL1_Standard/Sprint" in probe and "UAL1_Standard/Walk" in probe, "locomotion candidates are not explicitly sampled")
    require("sampled_position_tracks" in probe and "max_local_displacement_m" in probe and "path" in probe, "kinematic evidence schema incomplete")
    require("FOOT_TARGET_TOKENS" in probe and "leftfoot" in probe and "rightfoot" in probe, "bilateral foot contact targets are not pinned")
    require("CONTACT_HEIGHT_BAND_RATIO" in probe and "CONTACT_HEIGHT_BAND_MIN_M" in probe, "contact threshold is not deterministic")
    require("local_position_low_height_contact_proxy" in probe, "contact proxy method is not explicit")
    require("contact_sample_fraction" in probe and "contiguous_contact_slide_m" in probe and "mean_contact_slide_speed_mps" in probe, "contact-aware slide metrics missing")
    require('"grounding_verified": false' in probe and '"foot_slide_verified": false' in probe, "local contact proxy must never claim grounding/foot-slide verification")
    require('"contact_proxy_semantic_selection_allowed": false' in probe, "local contact proxy must not select run semantics")
    require("5c4dae72e49ad4e5959571e00a25d3d872cacba5.zip" in workflow, "source archive is not commit-pinned")
    require("Godot_v4.7.1-stable_linux.x86_64.zip" in workflow, "Godot 4.7.1 editor is not pinned")
    require("c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba" in workflow, "Godot binary SHA-256 is not pinned")
    require("exact_idle_candidates" in workflow and "exact_walk_candidates" in workflow and "exact_run_candidates" in workflow, "exact trio classification missing")
    require("foot_contact_proxy_count" in workflow and "foot_contact_proxies" in workflow, "workflow does not gate bilateral contact evidence")
    require("contact_proxy_is_ground_truth" in workflow and "False" in workflow, "workflow must state contact proxy is not ground truth")
    require("direct_adoption_allowed" in workflow and "False" in workflow, "characterization must remain fail-closed")
    require("actions/upload-artifact@v4" in workflow and "godot-characterization.json" in workflow, "measured evidence artifact is not published")
    print("QUATERNIUS_IK_CHARACTERIZATION_CONTRACT_OK: v4_contact_proxy=locked_fail_closed")


if __name__ == "__main__":
    main()