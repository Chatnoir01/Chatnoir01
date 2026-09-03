import copy
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
GEN_PATH = ROOT / "tools" / "generate_civ1_dynamic_z_component_candidate.py"
PATCH_PATH = ROOT / "tools" / "patch_civ1_dynamic_z_component_probe.py"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


generator = load(GEN_PATH, "dynamic_z_generator_for_probe")
patcher = load(PATCH_PATH, "dynamic_z_probe")

BASE = (
    "func _make_shadow_skeleton():\n"
    "    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n"
    "    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n"
    "    var left_foot_reference_ab = {}\n"
    "        var normalized_target_foot_origin := target_right_parent_pose.origin + target_right_parent_pose.basis * normalized_target_local_rest_origin\n"
)


def test_transform_wires_only_z_component_and_preserves_length_math():
    payload = generator.generate(8, 0.75)
    out = patcher.transform(BASE, payload)
    assert "CIV1_DYNAMIC_Z_COMPONENT_NATIVE_PROBE" in out
    assert "right_dynamic_source_z" in out
    assert "lerp(target_local_rest_origin.z, right_dynamic_source_z, right_dynamic_blend)" in out
    assert "right_dynamic_x: float = target_local_rest_origin.x" in out
    assert "right_dynamic_y_sq" in out
    assert "right_dynamic_sample_rest.length() - right_dynamic_length" in out
    assert "normalized_target_left_local_rest_origin := target_left_local_rest_origin" in out
    assert "Basis(Vector3.BACK" not in out
    assert "Basis(Vector3.RIGHT" not in out


def test_rejects_wrong_component_and_promotion_claims():
    payload = generator.generate(8, 0.5)
    forged = copy.deepcopy(payload)
    forged["component"] = "target_local_x"
    with pytest.raises(ValueError):
        patcher.transform(BASE, forged)
    forged = copy.deepcopy(payload)
    forged["runtime_authorized"] = True
    with pytest.raises(ValueError):
        patcher.transform(BASE, forged)


def test_rejects_outside_window_and_length_or_leftfoot_rail_drift():
    payload = generator.generate(8, 0.5)
    forged = copy.deepcopy(payload)
    forged["samples"][0]["z_component_blend"] = 0.1
    with pytest.raises(ValueError):
        patcher.transform(BASE, forged)
    forged = copy.deepcopy(payload)
    forged["samples"][59]["right_foot_length_error_m"] = 1.1e-6
    with pytest.raises(ValueError):
        patcher.transform(BASE, forged)
    forged = copy.deepcopy(payload)
    forged["samples"][59]["left_foot_delta_m"] = 1.1e-9
    with pytest.raises(ValueError):
        patcher.transform(BASE, forged)


def test_rejects_non_time_varying_and_outward_growing_taper_on_either_side():
    payload = generator.generate(8, 0.5)
    forged = copy.deepcopy(payload)
    for index, sample in enumerate(forged["samples"]):
        distance = min((index - 59) % 120, (59 - index) % 120)
        sample["z_component_blend"] = 0.5 if distance <= 8 else 0.0
    with pytest.raises(ValueError):
        patcher.transform(BASE, forged)

    forged = copy.deepcopy(payload)
    forged["samples"][60]["z_component_blend"] = forged["samples"][59]["z_component_blend"] + 0.01
    with pytest.raises(ValueError):
        patcher.transform(BASE, forged)

    forged = copy.deepcopy(payload)
    forged["samples"][58]["z_component_blend"] = forged["samples"][59]["z_component_blend"] + 0.01
    with pytest.raises(ValueError):
        patcher.transform(BASE, forged)


def test_rejects_anchor_drift_double_patch_and_forged_baseline():
    payload = generator.generate(8, 0.5)
    with pytest.raises(ValueError):
        patcher.transform(BASE.replace("normalized_target_left_local_rest_origin", "left_drift"), payload)
    forged = copy.deepcopy(payload)
    forged["baseline_source_plant_sample"] = 58
    with pytest.raises(ValueError):
        patcher.transform(BASE, forged)
    out = patcher.transform(BASE, payload)
    with pytest.raises(ValueError):
        patcher.transform(out, payload)
