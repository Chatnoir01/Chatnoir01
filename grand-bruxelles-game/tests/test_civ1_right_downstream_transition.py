from pathlib import Path
import importlib.util
import math
import pytest

SCRIPT = Path(__file__).parents[1] / "tools" / "analyze_civ1_right_downstream_transition.py"
spec = importlib.util.spec_from_file_location("transition", SCRIPT)
transition = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transition)


def _sample(index: int, right_downstream: float, left_downstream: float = 0.02):
    def chain(prefix: str, downstream: float):
        # source chain y: upper=0, lower=-0.4, foot=-0.8
        # target upper keeps a common-mode -0.06 m error; downstream is carried by foot-relative term.
        return {
            prefix + "UpperLeg": {
                "source": {"source_hips_relative_origin": [0.0, 0.0, 0.0]},
                "target": {"target_hips_relative_origin": [0.0, -0.06, 0.0]},
            },
            prefix + "LowerLeg": {
                "source": {"source_hips_relative_origin": [0.0, -0.4, 0.0]},
                "target": {"target_hips_relative_origin": [0.0, -0.46, 0.0]},
            },
            prefix + "Foot": {
                "source": {"source_hips_relative_origin": [0.0, -0.8, 0.0]},
                "target": {"target_hips_relative_origin": [0.0, -0.86 + downstream, 0.0]},
            },
        }
    bones = chain("Right", right_downstream)
    bones.update(chain("Left", left_downstream))
    return {"sample_index": index, "time_s": index / 180.0, "bones": bones}


def _payload():
    samples = []
    for i in range(89):
        downstream = 0.04 if i <= 78 else -0.01
        samples.append(_sample(i, downstream))
    return {"model_space_samples": samples}


def test_isolates_first_right_downstream_crossing_and_stays_diagnostic_only():
    result = transition.analyze(_payload())
    crossing = result["first_right_downstream_zero_crossing"]
    assert (crossing["from_sample"], crossing["to_sample"]) == (78, 79)
    assert result["runtime_authorized"] is False
    assert result["grounding_verified"] is False
    assert result["foot_slide_verified"] is False
    assert result["visual_approval_claimed"] is False


def test_rejects_missing_transition_crossing():
    payload = _payload()
    for i in range(58, 89):
        payload["model_space_samples"][i] = _sample(i, 0.03)
    with pytest.raises(ValueError, match="does not cross zero"):
        transition.analyze(payload)


def test_rejects_sample_index_drift_and_non_finite_terms():
    payload = _payload()
    payload["model_space_samples"][70]["sample_index"] = 69
    with pytest.raises(ValueError, match="sample index drift"):
        transition.analyze(payload)
    payload = _payload()
    payload["model_space_samples"][70]["bones"]["RightFoot"]["target"]["target_hips_relative_origin"][1] = math.nan
    with pytest.raises(ValueError, match="non-finite"):
        transition.analyze(payload)
