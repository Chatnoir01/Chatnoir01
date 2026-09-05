from __future__ import annotations

import copy
import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "tools" / "validate_civ1_sole_proxy_report.py"
spec = importlib.util.spec_from_file_location("sole_proxy_validator", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def _report() -> dict:
    samples = []
    captures = []
    for index in [114, 115, 116, 117, 118, 119]:
        samples.append(
            {
                "sample_index": index,
                "left_collider_name": "CanonicalMainGround",
                "right_collider_name": "CanonicalMainGround",
                "sole_proxy_collider_name": "CanonicalMainGround",
                "left_clearance_m": 0.010,
                "right_clearance_m": 0.020,
                "sole_proxy_clearance_m": 0.005,
            }
        )
        captures.append({"sample_index": index, "view": "low_side_contact"})
    return {
        "schema": "grand-bruxelles-civ1-left-ground-reference-v3",
        "diagnostic_only": True,
        "ground_contact_claimed": False,
        "rendered_sole_contact_claimed": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "reference_is_external_scene_ground": True,
        "reference_semantic": "canonical_main_ground_collision_raycast",
        "sole_proxy_semantic": "left_foot_bone_oriented_kinematic_proxy_not_rendered_mesh",
        "context_samples": [114, 115, 116, 117, 118, 119],
        "target_left_candidate_samples": [115, 116, 117, 118],
        "resolution": [1280, 720],
        "candidate_left_horizontal_path_m": 0.012,
        "candidate_sole_proxy_horizontal_path_m": 0.013,
        "candidate_left_min_clearance_m": 0.006,
        "candidate_left_max_clearance_m": 0.013,
        "candidate_sole_proxy_min_clearance_m": 0.002,
        "candidate_sole_proxy_max_clearance_m": 0.007,
        "max_pose_origin_error_m": 1e-7,
        "max_head_follow_error_m": 0.0,
        "samples": samples,
        "captures": captures,
    }


def _must_raise(report: dict) -> None:
    try:
        module.validate_report(report)
    except module.ReceiptError:
        return
    raise AssertionError("expected fail-closed ReceiptError")


def test_valid_proxy_receipt_stays_fail_closed() -> None:
    result = module.validate_report(_report())
    assert result["valid"] is True
    assert result["diagnostic_only"] is True
    assert result["rendered_sole_contact_claimed"] is False
    assert result["ground_contact_claimed"] is False
    assert result["runtime_authorized"] is False
    assert result["verdict"] == "AMELIORER_PROXY_RECEIPT_VALID_RENDERED_SOLE_UNPROVEN"


def test_forbidden_promotions_are_rejected() -> None:
    for field in (
        "rendered_sole_contact_claimed",
        "ground_contact_claimed",
        "runtime_authorized",
        "visual_approval_claimed",
        "player_view_claimed",
    ):
        report = _report()
        report[field] = True
        _must_raise(report)


def test_wrong_collider_is_rejected() -> None:
    report = _report()
    report["samples"][2]["sole_proxy_collider_name"] = "FakeGround"
    _must_raise(report)


def test_below_ground_proxy_is_rejected() -> None:
    report = _report()
    report["samples"][1]["sole_proxy_clearance_m"] = -0.001
    _must_raise(report)


def test_dynamic_technical_rail_is_rejected() -> None:
    report = _report()
    report["max_pose_origin_error_m"] = 0.0001001
    _must_raise(report)


def test_bad_sampling_and_resolution_are_rejected() -> None:
    report = _report()
    report["context_samples"] = [114, 115, 116]
    _must_raise(report)
    report = _report()
    report["resolution"] = [640, 360]
    _must_raise(report)


def main() -> None:
    test_valid_proxy_receipt_stays_fail_closed()
    test_forbidden_promotions_are_rejected()
    test_wrong_collider_is_rejected()
    test_below_ground_proxy_is_rejected()
    test_dynamic_technical_rail_is_rejected()
    test_bad_sampling_and_resolution_are_rejected()
    print("CIV1_SOLE_PROXY_REPORT_VALIDATOR_TESTS_OK")


if __name__ == "__main__":
    main()
