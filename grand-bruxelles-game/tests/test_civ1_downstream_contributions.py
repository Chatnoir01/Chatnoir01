from pathlib import Path
import importlib.util
import math
import pytest

SCRIPT = Path(__file__).parents[1] / "tools" / "analyze_civ1_downstream_contributions.py"
spec = importlib.util.spec_from_file_location("contrib", SCRIPT)
contrib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contrib)


def _bone(origin_y, motion_y, side):
    return {
        f"{side}_hips_relative_origin": [0.0, origin_y, 0.0],
        f"{side}_motion_from_rest": [0.0, motion_y, 0.0],
    }


def _sample(i, right_foot_rotation_error):
    bones = {}
    for prefix in ("Right", "Left"):
        bones[prefix + "UpperLeg"] = {
            "source": _bone(0.0, 0.0, "source"),
            "target": _bone(-0.06, 0.0, "target"),
        }
        bones[prefix + "LowerLeg"] = {
            "source": _bone(-0.4, 0.0, "source"),
            "target": _bone(-0.46, 0.0, "target"),
        }
        foot_motion = right_foot_rotation_error if prefix == "Right" else 0.01
        bones[prefix + "Foot"] = {
            "source": _bone(-0.8, 0.0, "source"),
            "target": _bone(-0.86 + foot_motion, foot_motion, "target"),
        }
    return {"sample_index": i, "time_s": i / 180.0, "bones": bones}


def _payload():
    samples = []
    for i in range(80):
        motion = 0.002 if i == 78 else (-0.002 if i == 79 else 0.01)
        samples.append(_sample(i, motion))
    return {
        "rotation_enabled": True,
        "position_enabled": False,
        "scale_enabled": False,
        "model_space_samples": samples,
    }


def test_decomposes_crossing_and_identifies_rotation_driver():
    result = contrib.analyze(_payload())
    driver = result["dominant_transition_driver"]
    assert driver["kind"] == "rotation_driven_delta_m"
    assert driver["link"] == "foot"
    assert result["right_transition_contributions"]["downstream"]["static_rest_delta_m"] == pytest.approx(0.0, abs=1e-12)
    assert result["right_transition_contributions"]["downstream"]["rotation_driven_delta_m"] == pytest.approx(-0.004)
    assert result["runtime_authorized"] is False
    assert result["visual_approval_claimed"] is False


def test_rejects_wrong_probe_modes_and_wrong_window():
    payload = _payload()
    payload["rotation_enabled"] = False
    with pytest.raises(ValueError, match="rotation-enabled"):
        contrib.analyze(payload)
    payload = _payload()
    payload["position_enabled"] = True
    with pytest.raises(ValueError, match="position/scale-disabled"):
        contrib.analyze(payload)
    with pytest.raises(ValueError, match="unsupported transition window"):
        contrib.analyze(_payload(), 77, 79)


def test_rejects_sample_drift_nonfinite_and_missing_expected_crossing():
    payload = _payload()
    payload["model_space_samples"][79]["sample_index"] = 78
    with pytest.raises(ValueError, match="sample index drift"):
        contrib.analyze(payload)
    payload = _payload()
    payload["model_space_samples"][79]["bones"]["RightFoot"]["target"]["target_motion_from_rest"][1] = math.nan
    with pytest.raises(ValueError, match="non-finite"):
        contrib.analyze(payload)
    payload = _payload()
    payload["model_space_samples"][79] = _sample(79, 0.003)
    with pytest.raises(ValueError, match="expected right downstream"):
        contrib.analyze(payload)
