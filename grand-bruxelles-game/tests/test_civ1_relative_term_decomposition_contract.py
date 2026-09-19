#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-relative-term-decomposition.yml"
GLOBAL_PROBE = ROOT / "tools" / "godot_civ1_global_chain_diagnostic.gd"


def require(text: str, token: str) -> None:
    assert token in text, f"missing contract token: {token}"


def main() -> None:
    assert GLOBAL_PROBE.exists(), "global-chain Godot probe missing"
    assert WORKFLOW.exists(), "relative-term decomposition workflow missing"

    workflow = WORKFLOW.read_text(encoding="utf-8")
    for token in (
        "Grand Bruxelles CIV-1 Relative Term Decomposition",
        "godot_civ1_global_chain_diagnostic.gd",
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "side_series('Right','source')",
        "side_series('Right','target')",
        "side_series('Left','source')",
        "side_series('Left','target')",
        "source_phase_window = list(range(58, 75))",
        "target_residual_window = list(range(84, 89))",
        "inverse_rotate",
        "local_offset_samples",
        "local_offset_span_m",
        "rotated_static_offset_vertical",
        "translation_residual_vertical",
        "translation_residual_max_abs_m",
        "static_offset_invariant",
        "relative_term_classification",
        "rotated_static_offset",
        "source_direction_target_length_counterfactual",
        "counterfactual_final_min_sample_index",
        "counterfactual_phase_delta_samples",
        "counterfactual_improves_phase",
        "left_control",
        "sample_count']==121",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
    ):
        require(workflow, token)

    print("CIV1_RELATIVE_TERM_DECOMPOSITION_CONTRACT_OK")


if __name__ == "__main__":
    main()
