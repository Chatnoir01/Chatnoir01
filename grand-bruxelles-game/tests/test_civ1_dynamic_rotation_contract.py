from pathlib import Path
import importlib.util

MODULE = Path(__file__).parents[1] / "tools" / "assess_civ1_dynamic_rotation_contract.py"
spec = importlib.util.spec_from_file_location("dyn", MODULE)
dyn = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(dyn)


def evidence():
    samples = []
    for i in range(12):
        angle = 0.0
        if i == 4:
            angle = 0.1
        elif i == 5:
            angle = 0.2
        elif i == 6:
            angle = 0.1
        samples.append({"rotation_delta_rad": angle, "right_foot_length_error_m": 0.0, "left_foot_delta_m": 0.0})
    return {"center_sample": 5, "radius_samples": 1, "cycle_sample_count": 12, "samples": samples}


def test_valid_dynamic_candidate_requires_native_measurement():
    out = dyn.assess(evidence())
    assert out["verdict"] == dyn.ALLOW
    assert out["runtime_authorized"] is False
    assert out["visual_approval_claimed"] is False


def test_static_rotation_family_fails_closed():
    data = evidence()
    for s in data["samples"]:
        s["rotation_delta_rad"] = 0.1
    assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_outside_window_mutation_fails_closed():
    data = evidence()
    data["samples"][10]["rotation_delta_rad"] = 0.01
    assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_length_or_leftfoot_mutation_fails_closed():
    data = evidence()
    data["samples"][5]["right_foot_length_error_m"] = 2e-6
    assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence()
    data["samples"][5]["left_foot_delta_m"] = 1e-8
    assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_constant_active_angle_is_not_time_varying():
    data = evidence()
    for i in (4, 5, 6):
        data["samples"][i]["rotation_delta_rad"] = 0.1
    assert dyn.assess(data)["verdict"] == dyn.BLOCK
