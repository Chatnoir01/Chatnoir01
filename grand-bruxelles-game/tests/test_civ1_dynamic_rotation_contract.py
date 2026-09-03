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
        elif distance == 2:
            angle = 0.05
        samples.append({"rotation_delta_rad": angle, "right_foot_length_error_m": 0.0, "left_foot_delta_m": 0.0})
    return {
        "candidate_kind": "civ1_rightfoot_dynamic_rotation_schedule",
        "candidate_is_native_measurement": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "center_sample": 59,
        "radius_samples": 2,
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


def test_radius_below_generator_domain_fails_closed():
    data = evidence(); data["radius_samples"] = 1; data["samples"][57]["rotation_delta_rad"] = 0.0; data["samples"][61]["rotation_delta_rad"] = 0.0
    assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_promotion_or_native_measurement_claims_fail_closed():
    for field in ("candidate_is_native_measurement", "runtime_authorized", "visual_approval_claimed"):
        data = evidence(); data[field] = True; assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence(); data["candidate_kind"] = "other"; assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence(); del data["runtime_authorized"]; assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_forged_self_consistent_baseline_fails_closed():
    data = evidence(); data["center_sample"] = 60; data["baseline_source_plant_sample"] = 60; assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence(); data["cycle_sample_count"] = 119; data["baseline_cycle_sample_count"] = 119; data["samples"] = data["samples"][:119]; assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_static_or_outside_window_rotation_fails_closed():
    data = evidence()
    for sample in data["samples"]: sample["rotation_delta_rad"] = 0.1
    assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence(); data["samples"][10]["rotation_delta_rad"] = 0.01; assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_length_leftfoot_center_and_taper_fail_closed():
    data = evidence(); data["samples"][59]["right_foot_length_error_m"] = 2e-6; assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence(); data["samples"][59]["left_foot_delta_m"] = 1e-8; assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence(); data["samples"][59]["rotation_delta_rad"] = 0.0; assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence(); data["samples"][58]["rotation_delta_rad"] = 0.30; data["samples"][60]["rotation_delta_rad"] = 0.30; assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_asymmetric_window_fails_closed():
    data = evidence(); data["samples"][58]["rotation_delta_rad"] = 0.09; data["samples"][60]["rotation_delta_rad"] = 0.10; assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence(); data["samples"][58]["rotation_delta_rad"] = -0.10; data["samples"][60]["rotation_delta_rad"] = 0.10; assert dyn.assess(data)["verdict"] == dyn.BLOCK


def test_bool_and_nonfinite_evidence_fails_closed():
    data = evidence(); data["baseline_source_plant_sample"] = True; assert dyn.assess(data)["verdict"] == dyn.BLOCK
    data = evidence(); data["samples"][59]["rotation_delta_rad"] = float("nan"); assert dyn.assess(data)["verdict"] == dyn.BLOCK
