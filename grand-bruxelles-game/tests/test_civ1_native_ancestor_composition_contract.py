from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-civ1-native-ancestor-composition.yml"
GLOBAL_PROBE = ROOT / "grand-bruxelles-game/tools/godot_civ1_global_chain_diagnostic.gd"


def require(text: str, token: str) -> None:
    assert token in text, f"missing required token: {token}"


def main() -> None:
    assert GLOBAL_PROBE.exists(), "global-chain probe must remain versioned"
    assert WORKFLOW.exists(), "dedicated native ancestor composition workflow is required"
    text = WORKFLOW.read_text(encoding="utf-8")

    for token in (
        "Grand Bruxelles CIV-1 Native Ancestor Composition",
        "test_civ1_native_ancestor_composition_contract.py",
        "godot_civ1_global_chain_diagnostic.gd",
        "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "SOURCE_SUPPORT = range(58, 75)",
        "FALSE_SUPPORT = range(84, 89)",
        "SOURCE_CONTACT_INDEX = 59",
        "FALSE_CONTACT_INDEX = 86",
        "upperleg_hips_relative",
        "lowerleg_relative",
        "foot_relative",
        "downstream_sum",
        "algebraic_closure_error_m",
        "dominant_false_window_term",
        "source_downstream_compensates_upperleg",
        "false_downstream_reinforces_upperleg",
        "diagnostic_only",
        "runtime_authorized",
        "visual_approval_claimed",
        "threshold_was_modified",
    ):
        require(text, token)

    for forbidden in (
        "run_alias_selected: true",
        "runtime_authorized: true",
        "visual_approval_claimed: true",
        "threshold_was_modified: true",
    ):
        assert forbidden not in text, f"forbidden authorization/rescue token: {forbidden}"

    print("CIV1_NATIVE_ANCESTOR_COMPOSITION_CONTRACT_OK")


if __name__ == "__main__":
    main()
