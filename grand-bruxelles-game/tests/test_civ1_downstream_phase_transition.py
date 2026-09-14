from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANALYZER = ROOT / "grand-bruxelles-game/tools/analyze_civ1_downstream_phase_transition.py"


def _load():
    spec = spec_from_file_location("civ1_transition", ANALYZER)
    assert spec and spec.loader
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _point(y):
    return [0.0, float(y), 0.0]


def _payload():
    samples = []
    for i in range(121):
        # Right downstream is +45 mm before the transition. LowerLeg begins
        # changing first (index 66), Foot follows (index 71), and their sum
        # reaches exact zero at index 76 before becoming reinforcing.
        right_upper_src = 1.0
        right_upper_tgt = 0.94
        right_lower_src = 0.55
        right_foot_src = 0.10
        lower_err = 0.025 - max(0, i - 65) * 0.003
        foot_err = 0.020 - max(0, i - 70) * 0.002
        right_lower_tgt = right_upper_tgt + (right_lower_src - right_upper_src) + lower_err
        right_foot_tgt = right_lower_tgt + (right_foot_src - right_lower_src) + foot_err

        # Left control remains compensating through the full diagnostic window.
        left_upper_src = 1.0
        left_upper_tgt = 0.94
        left_lower_src = 0.55
        left_foot_src = 0.10
        left_lower_tgt = left_upper_tgt + (left_lower_src - left_upper_src) + 0.020
        left_foot_tgt = left_lower_tgt + (left_foot_src - left_lower_src) + 0.015

        bones = {}
        for prefix, vals in {
            "Right": (right_upper_src, right_upper_tgt, right_lower_src, right_lower_tgt, right_foot_src, right_foot_tgt),
            "Left": (left_upper_src, left_upper_tgt, left_lower_src, left_lower_tgt, left_foot_src, left_foot_tgt),
        }.items():
            us, ut, ls, lt, fs, ft = vals
            bones[prefix + "UpperLeg"] = {
                "source": {"source_hips_relative_origin": _point(us)},
                "target": {"target_hips_relative_origin": _point(ut)},
            }
            bones[prefix + "LowerLeg"] = {
                "source": {"source_hips_relative_origin": _point(ls)},
                "target": {"target_hips_relative_origin": _point(lt)},
            }
            bones[prefix + "Foot"] = {
                "source": {"source_hips_relative_origin": _point(fs)},
                "target": {"target_hips_relative_origin": _point(ft)},
            }
        samples.append({"bones": bones})
    return {
        "format": "grand-bruxelles-civ1-global-chain-diagnostic-v3",
        "sample_count": 121,
        "retarget_modifier": "RetargetModifier3D",
        "position_enabled": False,
        "rotation_enabled": True,
        "scale_enabled": False,
        "model_space_samples": samples,
    }


def main():
    assert ANALYZER.exists()
    module = _load()
    result = module.analyze(_payload())
    assert result["format"] == "grand-bruxelles-civ1-downstream-phase-transition-v2"
    assert result["right_first_cross_index"] == 76
    assert result["left_first_cross_index"] is None

    right = result["right"]
    crossings = right["first_zero_cross_by_term"]
    assert crossings["lowerleg_relative_m"]["index"] == 74
    assert crossings["lowerleg_relative_m"]["kind"] == "sign_cross"
    assert 73.0 < crossings["lowerleg_relative_m"]["interpolated_index"] < 74.0
    assert crossings["foot_relative_m"]["index"] == 80
    assert crossings["foot_relative_m"]["kind"] == "exact_zero"
    assert crossings["downstream_sum_m"]["index"] == 76
    assert crossings["downstream_sum_m"]["kind"] == "exact_zero"

    driver = right["downstream_cross_driver"]
    assert driver["interval"] == [75, 76]
    assert abs(driver["lowerleg_delta_m"] + 0.003) < 1e-12
    assert abs(driver["foot_delta_m"] + 0.002) < 1e-12
    assert abs(driver["downstream_delta_m"] + 0.005) < 1e-12
    assert driver["largest_absolute_delta_term"] == "lowerleg_relative"

    lower_step = right["largest_step_by_term"]["lowerleg_relative_m"]
    foot_step = right["largest_step_by_term"]["foot_relative_m"]
    assert abs(lower_step["abs_delta_m"] - 0.003) < 1e-12
    assert abs(foot_step["abs_delta_m"] - 0.002) < 1e-12

    assert result["diagnostic_only"] is True
    assert result["threshold_was_modified"] is False
    assert result["runtime_authorized"] is False
    assert result["visual_approval_claimed"] is False
    print("CIV1_DOWNSTREAM_PHASE_TRANSITION_TEST_OK")


if __name__ == "__main__":
    main()
