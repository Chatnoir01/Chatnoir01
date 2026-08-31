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
    require("grand-bruxelles-quaternius-ik-godot-characterization-v2" in probe, "probe format is not pinned to v2")
    require("Skeleton3D" in probe and "AnimationPlayer" in probe, "probe must inspect skeletons and animation players")
    require("skinned_mesh_count" in probe and "bone_names" in probe and "animation_names" in probe, "probe metrics incomplete")
    require("animation_metrics" in probe and "length_seconds" in probe and "loop_mode" in probe and "track_count" in probe, "locomotion semantic metrics missing")
    require("animation_metric_conflicts" in probe, "duplicate animation metric conflict detection missing")
    require("5c4dae72e49ad4e5959571e00a25d3d872cacba5.zip" in workflow, "source archive is not commit-pinned")
    require("Godot_v4.7.1-stable_linux.x86_64.zip" in workflow, "Godot 4.7.1 editor is not pinned")
    require("c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba" in workflow, "Godot binary SHA-256 is not pinned")
    require("exact_idle_candidates" in workflow and "exact_walk_candidates" in workflow and "exact_run_candidates" in workflow, "exact trio classification missing")
    require("direct_adoption_allowed" in workflow and "False" in workflow, "characterization must remain fail-closed")
    require("actions/upload-artifact@v4" in workflow and "godot-characterization.json" in workflow, "measured evidence artifact is not published")
    print("QUATERNIUS_IK_CHARACTERIZATION_CONTRACT_OK")


if __name__ == "__main__":
    main()
