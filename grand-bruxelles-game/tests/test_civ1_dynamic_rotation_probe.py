#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(mod)
    return mod


gen = load("gen", ROOT / "tools" / "generate_civ1_dynamic_rotation_candidate.py")
probe = load("probe", ROOT / "tools" / "patch_civ1_dynamic_rotation_probe.py")

BASE = (
    "func _make_shadow_skeleton():\n    pass\n"
    "# left_foot_reference_ab\n"
    + probe.RIGHT
    + probe.LEFT
    + "func sample_loop():\n"
    + probe.SAMPLE
)


def assert_rejected(payload: dict, message: str) -> None:
    try:
        probe.transform(BASE, payload)
    except ValueError:
        return
    raise AssertionError(message)


def test_valid_probe_transform_inserts_dynamic_schedule_once():
    payload = gen.generate(4, 0.20)
    out = probe.transform(BASE, payload)
    assert probe.MARKER in out
    assert "PackedFloat64Array" in out
    assert "Basis(Vector3.RIGHT, right_dynamic_angle)" in out
    assert "normalized_target_local_rest_origin := target_local_rest_origin" in out
    assert "normalized_target_left_local_rest_origin := target_left_local_rest_origin" in out
    assert "right_dynamic_sample_rest.normalized() * target_local_rest_origin.length()" in out
    assert "> 0.000001" in out
    assert "> 0.000000001" not in out
    assert probe.NATIVE_LENGTH_TOLERANCE_M == 1e-6
    assert probe.RIGHT not in out and probe.LEFT not in out and probe.SAMPLE not in out
    try:
        probe.transform(out, payload)
    except ValueError:
        pass
    else:
        raise AssertionError("double dynamic rotation patch accepted")


def test_probe_rejects_identity_and_promotion_forgery():
    for field, value in (
        ("center_sample", 58),
        ("cycle_sample_count", 119),
        ("candidate_is_native_measurement", True),
        ("runtime_authorized", True),
        ("visual_approval_claimed", True),
    ):
        bad = gen.generate(4, 0.20)
        bad[field] = value
        assert_rejected(bad, f"invalid {field} accepted")


def test_probe_rejects_out_of_window_and_bilateral_rail_mutations():
    bad = gen.generate(4, 0.20)
    bad["samples"][10]["rotation_delta_rad"] = 0.01
    assert_rejected(bad, "out-of-window rotation accepted")

    bad = gen.generate(4, 0.20)
    bad["samples"][59]["left_foot_delta_m"] = 1e-8
    assert_rejected(bad, "LeftFoot mutation rail bypassed")

    bad = gen.generate(4, 0.20)
    bad["samples"][59]["right_foot_length_error_m"] = 1.1e-6
    assert_rejected(bad, "RightFoot contract length rail bypassed")


def test_probe_accepts_contract_edge_length_error():
    edge = gen.generate(4, 0.20)
    edge["samples"][59]["right_foot_length_error_m"] = 1e-6
    out = probe.transform(BASE, edge)
    assert "right_dynamic_sample_rest.normalized()" in out


def test_probe_rejects_static_active_rotation():
    bad = gen.generate(4, 0.20)
    for sample in bad["samples"]:
        if abs(sample["rotation_delta_rad"]) > 1e-12:
            sample["rotation_delta_rad"] = 0.2
    assert_rejected(bad, "static active rotation accepted")
