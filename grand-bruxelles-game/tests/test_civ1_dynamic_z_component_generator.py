import importlib.util
import math
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "generate_civ1_dynamic_z_component_candidate.py"
spec = importlib.util.spec_from_file_location("dynamic_z_generator", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def test_generates_symmetric_bounded_taper_and_no_promotion_claims():
    payload = module.generate(8, 0.75)
    assert payload["candidate_kind"] == "civ1_rightfoot_dynamic_z_component_schedule"
    assert payload["component"] == "target_local_rest_z"
    assert payload["center_sample"] == 59
    assert payload["cycle_sample_count"] == 120
    assert payload["runtime_authorized"] is False
    assert payload["visual_approval_claimed"] is False
    samples = payload["samples"]
    assert len(samples) == 120
    assert samples[59]["z_component_blend"] == pytest.approx(0.75)
    assert samples[58]["z_component_blend"] == pytest.approx(samples[60]["z_component_blend"])
    assert samples[51]["z_component_blend"] == pytest.approx(samples[67]["z_component_blend"])
    assert samples[50]["z_component_blend"] == 0.0
    assert samples[68]["z_component_blend"] == 0.0
    assert samples[59]["z_component_blend"] > samples[60]["z_component_blend"] > samples[61]["z_component_blend"]
    assert all(sample["right_foot_length_error_m"] == 0.0 for sample in samples)
    assert all(sample["left_foot_delta_m"] == 0.0 for sample in samples)


@pytest.mark.parametrize("radius", [True, 0, 1, 60, 120])
def test_rejects_invalid_radius(radius):
    with pytest.raises(ValueError):
        module.generate(radius, 0.5)


@pytest.mark.parametrize("peak", [True, 0.0, -0.1, 1.0001, float("nan"), float("inf")])
def test_rejects_invalid_peak(peak):
    with pytest.raises(ValueError):
        module.generate(8, peak)


def test_taper_is_finite_and_monotone_on_both_sides():
    payload = module.generate(12, 1.0)
    samples = payload["samples"]
    for distance in range(13):
        left = samples[(59 - distance) % 120]["z_component_blend"]
        right = samples[(59 + distance) % 120]["z_component_blend"]
        assert math.isfinite(left) and math.isfinite(right)
        assert left == pytest.approx(right)
        if distance:
            previous = samples[(59 + distance - 1) % 120]["z_component_blend"]
            assert right <= previous + 1e-12
