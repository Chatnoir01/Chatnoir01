from pathlib import Path
import importlib.util

MODULE = Path(__file__).parents[1] / "tools" / "assess_civ1_dynamic_rotation_contract.py"
spec = importlib.util.spec_from_file_location("dyn", MODULE)
dyn = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(dyn)


def evidence():
    samples = []
    for i in range(120):
        distance = min((i - 59) % 120, (59 - i) % 120)
        angle = 0.0
        if distance == 0:
            angle = 0.20
        elif distance == 1:
            angle = 0.10
        samples.append({"rotation_delta_rad": angle, "right_foot_length_error_m": 0.0, "left_foot_delta_m": 0.0})
    return {
        "center_sample": 59,
        "radius_samples": 1,
        "cycle_sample_count": 120,
        "baseline_source_plant_sample": 59,
        "baseline_cycle_sample_count": 120,
        "samples": samples,
    }


def test_valid_dynamic_candidate_requires_native_measurement():
    out = dyn.assess(evidence())
    assert out["verdict"] == dyn.ALLOW
    assert out["bound_source_plant_sample"] == 59
    assert out["bound_cycle_sample_count"] == 120
    assert out["runtime_authorized"] is False
    assert out["visual_approval_claimed"] is False


def test_forged_self_consistent_baseline_fails_closed():
    data = evidence()
    data["center_sample"] = 60
    data["baseline_source_plant_sample"] = 60
    assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence()
    data["cycle_sample_count"] = 119
    data["baseline_cycle_sample_count"] = 119
    data["samples"] = data["samples"][:119]
    assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_declared_candidate_must_match_bound_baseline():
    data = evidence()
    data["center_sample"] = 60
    assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_static_or_outside_window_rotation_fails_closed():
    data = evidence()
    for sample in data["samples"]:
        sample["rotation_delta_rad"] = 0.1
    assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence()
    data["samples"][10]["rotation_delta_rad"] = 0.01
    assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_length_or_leftfoot_mutation_fails_closed():
    data = evidence()
    data["samples"][59]["right_foot_length_error_m"] = 2e-6
    assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence()
    data["samples"][59]["left_foot_delta_m"] = 1e-8
    assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_center_must_be_active_and_taper_must_not_grow_outward():
    data = evidence()
    data["samples"][59]["rotation_delta_rad"] = 0.0
    assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence()
    data["samples"][58]["rotation_delta_rad"] = 0.30
    data["samples"][60]["rotation_delta_rad"] = 0.30
    assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_bool_and_nonfinite_evidence_fails_closed():
    data = evidence()
    data["baseline_source_plant_sample"] = True
    assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence()
    data["samples"][59]["rotation_delta_rad"] = float("nan")
    assert dyn.assess(data)["verdict"] == dyn.BLOCK
