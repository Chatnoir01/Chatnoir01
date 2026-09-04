from pathlib import Path
import importlib.util
import math
import pytest

SCRIPT = Path(__file__).parents[1] / "tools" / "analyze_civ1_foot_link_projection.py"
spec = importlib.util.spec_from_file_location("foot_link_projection", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def _qx(deg: float):
    h = math.radians(deg) / 2.0
    return [math.sin(h), 0.0, 0.0, math.cos(h)]


def _rotate(q, v):
    return mod._mul(mod._matrix(mod._quat(q, "q")), v)


def _bone(origin, q):
    return {"model_origin": origin, "model_rotation_xyzw": q}


def _sample(index: int, right_src_deg: float, right_tgt_deg: float, left_src_deg: float, left_tgt_deg: float):
    bones = {}
    rests = {
        ("Right", "source"): [0.0, 0.45, 0.05],
        ("Right", "target"): [0.0, 0.42, 0.0],
        ("Left", "source"): [0.0, 0.45, 0.05],
        ("Left", "target"): [0.0, 0.42, 0.0],
    }
    degs = {
        ("Right", "source"): right_src_deg,
        ("Right", "target"): right_tgt_deg,
        ("Left", "source"): left_src_deg,
        ("Left", "target"): left_tgt_deg,
    }
    for prefix in ("Right", "Left"):
        bones[prefix + "LowerLeg"] = {}
        bones[prefix + "Foot"] = {}
        for side in ("source", "target"):
            q = _qx(degs[(prefix, side)])
            parent = [0.0, 0.0, 0.0]
            link = _rotate(q, rests[(prefix, side)])
            child = [parent[i] + link[i] for i in range(3)]
            bones[prefix + "LowerLeg"][side] = _bone(parent, q)
            bones[prefix + "Foot"][side] = _bone(child, [0.0, 0.0, 0.0, 1.0])
    return {"sample_index": index, "time_s": index / 180.0, "bones": bones}


def _payload():
    samples = [_sample(i, 0, 0, 0, 0) for i in range(80)]
    samples[78] = _sample(78, 0.0, 0.0, 0.0, 0.0)
    samples[79] = _sample(79, 5.0, 15.0, 2.0, 3.0)
    return {"rotation_enabled": True, "position_enabled": False, "scale_enabled": False, "model_space_samples": samples}


def test_projection_closes_and_identifies_parent_rotation():
    result = mod.analyze(_payload())
    right = result["right_foot_link"]
    assert result["causal_parent"] == "LowerLeg model rotation"
    assert result["child_foot_rotation_controls_origin"] is False
    assert right["foot_link_error_delta_m"] < 0.0
    assert abs(right["projection_closure_error_m"]) < 3e-7
    assert right["dominant_rest_axis"] in {"y", "z"}
    assert result["runtime_authorized"] is False
    assert result["visual_approval_claimed"] is False


def test_rejects_wrong_probe_mode():
    payload = _payload(); payload["position_enabled"] = True
    with pytest.raises(ValueError, match="position/scale-disabled"):
        mod.analyze(payload)


def test_rejects_sample_drift():
    payload = _payload(); payload["model_space_samples"][79]["sample_index"] = 78
    with pytest.raises(ValueError, match="sample index drift"):
        mod.analyze(payload)


def test_rejects_non_finite_rotation():
    payload = _payload(); payload["model_space_samples"][78]["bones"]["RightLowerLeg"]["source"]["model_rotation_xyzw"][0] = float("nan")
    with pytest.raises(ValueError, match="non-finite"):
        mod.analyze(payload)


def test_rejects_degenerate_rotation():
    payload = _payload(); payload["model_space_samples"][78]["bones"]["RightLowerLeg"]["source"]["model_rotation_xyzw"] = [0.0, 0.0, 0.0, 0.0]
    with pytest.raises(ValueError, match="degenerate"):
        mod.analyze(payload)


def test_rejects_rest_drift_between_samples():
    payload = _payload()
    payload["model_space_samples"][79]["bones"]["RightFoot"]["source"]["model_origin"][0] += 0.01
    with pytest.raises(ValueError, match="rest-local drift"):
        mod.analyze(payload)
