from pathlib import Path
import importlib.util
import math
import pytest

ROOT = Path(__file__).parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(mod)
    return mod


gen = load("gen", ROOT / "tools" / "generate_civ1_dynamic_rotation_candidate.py")
contract = load("contract", ROOT / "tools" / "assess_civ1_dynamic_rotation_contract.py")


def test_generated_candidate_passes_structural_contract_only():
    data = gen.generate(4, 0.20)
    out = contract.assess(data)
    assert out["verdict"] == contract.ALLOW
    assert data["candidate_is_native_measurement"] is False
    assert data["runtime_authorized"] is False
    assert data["visual_approval_claimed"] is False
    assert out["runtime_authorized"] is False
    assert out["visual_approval_claimed"] is False


def test_schedule_is_centered_bounded_symmetric_and_tapered():
    data = gen.generate(4, 0.20)
    s = data["samples"]
    center = gen.CENTER_SAMPLE
    assert s[center]["rotation_delta_rad"] == pytest.approx(0.20)
    for d in range(1, 5):
        left = s[(center - d) % 120]["rotation_delta_rad"]
        right = s[(center + d) % 120]["rotation_delta_rad"]
        assert left == pytest.approx(right)
        assert 0.0 < left < s[(center - (d - 1)) % 120]["rotation_delta_rad"]
    assert s[(center - 5) % 120]["rotation_delta_rad"] == 0.0
    assert s[(center + 5) % 120]["rotation_delta_rad"] == 0.0


def test_schedule_preserves_declared_bilateral_structural_rails():
    data = gen.generate(8, -0.15)
    for sample in data["samples"]:
        assert sample["right_foot_length_error_m"] == 0.0
        assert sample["left_foot_delta_m"] == 0.0
        assert math.isfinite(sample["rotation_delta_rad"])


@pytest.mark.parametrize("radius", [True, 0, 1, 60, 120])
def test_invalid_radius_fails_closed(radius):
    with pytest.raises(ValueError):
        gen.generate(radius, 0.20)


@pytest.mark.parametrize("peak", [True, 0.0, float("nan"), float("inf"), math.pi])
def test_invalid_peak_fails_closed(peak):
    with pytest.raises(ValueError):
        gen.generate(4, peak)
