from pathlib import Path

PROBE = Path("grand-bruxelles-game/tools/godot_quaternius_support_window_probe.gd")
WORKFLOW = Path(".github/workflows/grand-bruxelles-quaternius-support-window.yml")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"QUATERNIUS_SUPPORT_WINDOW_CONTRACT_FAIL: {message}")


def main() -> None:
    probe = PROBE.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    require('const SAMPLE_COUNT := 121' in probe, "sample count drifted")
    require('const LOW_BAND_FRACTION := 0.10' in probe, "support low-band fraction drifted")
    require('"UAL1_Standard/Jog_Fwd"' in probe and '"UAL1_Standard/Sprint"' in probe, "candidate pair drifted")
    require('await process_frame' in probe, "frame-settled pose evaluation removed")
    require('terminal_loop_sample_excluded_from_support_mask' in probe, "loop seam exclusion contract missing")
    require('contiguous_source_relative_bottom_10_percent_windows_per_foot' in probe, "support definition drifted")
    require('"bilateral_support_fraction"' in probe, "bilateral support metric missing")
    require('"unilateral_support_fraction"' in probe, "unilateral support metric missing")
    require('"neither_low_fraction"' in probe, "flight/neither-low metric missing")
    require('"horizontal_displacement_m"' in probe and '"horizontal_path_m"' in probe, "window drift metrics missing")
    require('"diagnostic_only": true' in probe, "diagnostic-only rail opened")
    require('"world_ground_assumed": false' in probe, "world-ground assumption opened")
    require('"contact_verified": false' in probe, "contact verification opened")
    require('"semantic_selection_allowed": false' in probe, "semantic selection opened")
    require('"selected_run_alias": ""' in probe, "Run alias selected")
    require('"civ1_retarget_authorized": false' in probe, "CIV-1 retarget authorized")
    require('"grounding_verified": false' in probe, "grounding verification opened")
    require('"foot_slide_verified": false' in probe, "foot-slide verification opened")
    require('"visual_approval_claimed": false' in probe, "visual approval opened")

    require('Godot_v4.7.1-stable_linux.x86_64.zip' in workflow, "Godot 4.7.1 pin missing")
    require('c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba' in workflow, "Godot archive hash pin missing")
    require('f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767' in workflow, "Quaternius archive hash pin missing")
    require('38687957' in workflow, "Quaternius archive size pin missing")
    require('cc0|creative commons zero' in workflow.lower(), "CC0 verification missing")
    require('if: always()' in workflow, "failure artifact preservation missing")
    require("semantic_selection_allowed'] is False" in workflow, "workflow semantic rail missing")
    require("contact_verified'] is False" in workflow, "workflow contact rail missing")

    print("QUATERNIUS_SUPPORT_WINDOW_CONTRACT_OK")


if __name__ == "__main__":
    main()
