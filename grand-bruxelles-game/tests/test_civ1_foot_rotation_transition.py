from pathlib import Path
import importlib.util
import math
import pytest

SCRIPT = Path(__file__).parents[1] / "tools" / "analyze_civ1_foot_rotation_transition.py"
spec = importlib.util.spec_from_file_location("rotation_transition", SCRIPT)
rotation_transition = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rotation_transition)


def _qz(deg: float):
    half = math.radians(deg) / 2.0
    return [0.0, 0.0, math.sin(half), math.cos(half)]


def _sample(index: int, right_source: float, right_target: float, left_source: float, left_target: float):
    return {
        "sample_index": index,
        "time_s": index / 180.0,
        "bones": {
            "RightFoot": {
                "source": {"model_rotation_xyzw": _qz(right_source)},
                "target": {"model_rotation_xyzw": _qz(right_target)},
            },
            "LeftFoot": {
                "source": {"model_rotation_xyzw": _qz(left_source)},
                "target": {"model_rotation_xyzw": _qz(left_target)},
            },
        },
    }


def _payload():
    samples = [_sample(i, 0.0, 0.0, 0.0, 0.0) for i in range(80)]
    samples[78] = _sample(78, 10.0, 20.0, 5.0, 10.0)
    samples[79] = _sample(79, 12.0, 25.0, 7.0, 13.0)
    return {
        "rotation_enabled": True,
        "position_enabled": False,
        "scale_enabled": False,
        "model_space_samples": samples,
    }


def test_isolates_target_vs_source_error_delta_and_left_control():
    result = rotation_transition.analyze(_payload())
    right = result["right_foot"]["target_vs_source_error_delta_78_to_79"]
    left = result["left_foot_control"]["target_vs_source_error_delta_78_to_79"]
    assert right["angle_deg"] == pytest.approx(3.0, abs=1e-9)
    assert left["angle_deg"] == pytest.approx(1.0, abs=1e-9)
    assert result["right_minus_left_error_delta_angle_deg"] == pytest.approx(2.0, abs=1e-9)
    assert result["runtime_authorized"] is False
    assert result["visual_approval_claimed"] is False


def test_quaternion_sign_flip_does_not_forge_rotation_delta():
    payload = _payload()
    for side in ("source", "target"):
        q = payload["model_space_samples"][79]["bones"]["RightFoot"][side]["model_rotation_xyzw"]
        payload["model_space_samples"][79]["bones"]["RightFoot"][side]["model_rotation_xyzw"] = [-v for v in q]
    result = rotation_transition.analyze(payload)
    assert result["right_foot"]["target_vs_source_error_delta_78_to_79"]["angle_deg"] == pytest.approx(3.0, abs=1e-9)


def test_rejects_wrong_probe_mode_window_sample_drift_and_bad_quaternion():
    payload = _payload()
    payload["rotation_enabled"] = False
    with pytest.raises(ValueError, match="rotation-enabled"):
        rotation_transition.analyze(payload)
    with pytest.raises(ValueError, match="unsupported transition window"):
        rotation_transition.analyze(_payload(), 77, 79)
    payload = _payload()
    payload["model_space_samples"][79]["sample_index"] = 78
    with pytest.raises(ValueError, match="sample index drift"):
        rotation_transition.analyze(payload)
    payload = _payload()
    payload["model_space_samples"][79]["bones"]["RightFoot"]["target"]["model_rotation_xyzw"][0] = math.nan
    with pytest.raises(ValueError, match="non-finite"):
        rotation_transition.analyze(payload)
    payload = _payload()
    payload["model_space_samples"][79]["bones"]["RightFoot"]["target"]["model_rotation_xyzw"] = [0.0, 0.0, 0.0, 0.0]
    with pytest.raises(ValueError, match="degenerate"):
        rotation_transition.analyze(payload)
