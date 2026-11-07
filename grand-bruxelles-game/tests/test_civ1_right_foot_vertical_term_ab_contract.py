from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-civ1-right-foot-vertical-term-ab.yml"


def require(text: str, needle: str) -> None:
    assert needle in text, f"missing RightFoot vertical-term A-B token: {needle}"


def main() -> None:
    assert WORKFLOW.exists(), "RightFoot vertical-term A-B workflow must exist"
    text = WORKFLOW.read_text(encoding="utf-8")

    # Keep the exact validated bench identities and frozen measurement shape.
    for token in (
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "Godot_v4.7.1-stable_linux.x86_64",
        "UAL1_Standard/Sprint",
        "sample_count']==121",
        "support_band_fraction']==0.10",
    ):
        require(text, token)

    # The intervention is deliberately one-term only: retain target local Y,
    # preserve exact target foot length, source-constrain only the XZ direction.
    for token in (
        "preserved_y := target_right_foot_original_local_rest_origin.y",
        "target_length := target_right_foot_original_local_rest_origin.length()",
        "source_horizontal := Vector2(normalized_local_direction.x, normalized_local_direction.z)",
        "source_global_reference_direction_xz_preserve_target_local_y_and_length",
        "target_right_foot_length_preserved",
    ):
        require(text, token)

    # Both candidates must be measured from the same import and classified
    # against the exact source proxy; no absolute gameplay tolerance is invented.
    for token in (
        "full-normalized.json",
        "preserve-local-y.json",
        "source_relative_plane_error_m",
        "plane_error_improves_over_full",
        "median_horizontal_speed_mps",
        "p90_horizontal_speed_mps",
        "low_height_windows",
        "secondary_window_removed",
        "diagnostic_only",
        "world_ground_assumed",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(text, token)

    print("civ1 RightFoot vertical-term A-B contract OK")


if __name__ == "__main__":
    main()
