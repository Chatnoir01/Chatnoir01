from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSESSOR = ROOT / "grand-bruxelles-game/tools/assess_civ1_bilateral_patch_scope.py"


def _load():
    spec = spec_from_file_location("civ1_bilateral_scope", ASSESSOR)
    assert spec and spec.loader
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _cross(value):
    return {"interpolated_index": value}


def _side(driver, foot_cross, lowerleg_cross=59.90):
    side = {"first_zero_cross_by_term": {}}
    if foot_cross is not None:
        side["first_zero_cross_by_term"]["foot_relative_m"] = _cross(foot_cross)
    if lowerleg_cross is not None:
        side["first_zero_cross_by_term"]["lowerleg_relative_m"] = _cross(lowerleg_cross)
    if driver is not None:
        side["downstream_cross_driver"] = {"largest_absolute_delta_term": driver}
    return side


def _payload(
    right_driver="foot_relative",
    left_driver="foot_relative",
    right_cross=78.46,
    left_cross=82.30,
    right_lowerleg_cross=59.90,
    left_lowerleg_cross=60.10,
):
    return {
        "format": "grand-bruxelles-civ1-downstream-phase-transition-v2",
        "right": _side(right_driver, right_cross, right_lowerleg_cross),
        "left_control": _side(left_driver, left_cross, left_lowerleg_cross),
        "diagnostic_only": True,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
    }


def main():
    assert ASSESSOR.exists()
    module = _load()

    blocked = module.assess(_payload(), "right_only")
    assert blocked["same_dominant_downstream_driver"] is True
    assert blocked["bilateral_foot_implication"] is True
    assert blocked["unilateral_scope_authorized"] is False
    assert blocked["scope_verdict"] == "BLOCK_UNILATERAL_SCOPE"
    assert blocked["reason"] == "same_dominant_downstream_driver_on_both_sides"
    assert abs(blocked["foot_phase_skew_samples"] - 3.84) < 1e-12

    bilateral = module.assess(_payload(), "bilateral")
    assert bilateral["unilateral_scope_authorized"] is True
    assert bilateral["scope_verdict"] == "ALLOW_QA_SCOPE"
    assert bilateral["grounding_verified"] is False
    assert bilateral["foot_slide_verified"] is False
    assert bilateral["runtime_authorized"] is False
    assert bilateral["visual_approval_claimed"] is False

    asymmetric = module.assess(_payload(left_driver="lowerleg_relative"), "right_only")
    assert asymmetric["same_dominant_downstream_driver"] is False
    assert asymmetric["bilateral_foot_implication"] is False
    assert asymmetric["evidence_complete"] is True
    assert asymmetric["unilateral_scope_authorized"] is True

    missing_driver_cross = module.assess(
        _payload(left_driver="lowerleg_relative", left_lowerleg_cross=None),
        "right_only",
    )
    assert missing_driver_cross["evidence_complete"] is False
    assert missing_driver_cross["unilateral_scope_authorized"] is False
    assert missing_driver_cross["scope_verdict"] == "BLOCK_INCOMPLETE_EVIDENCE"
    assert missing_driver_cross["reason"] == "bilateral_driver_or_driver_crossing_missing"

    missing_driver = module.assess(_payload(left_driver=None), "right_only")
    assert missing_driver["evidence_complete"] is False
    assert missing_driver["unilateral_scope_authorized"] is False
    assert missing_driver["scope_verdict"] == "BLOCK_INCOMPLETE_EVIDENCE"
    assert missing_driver["reason"] == "bilateral_driver_or_driver_crossing_missing"

    missing_cross = module.assess(_payload(left_cross=None), "right_only")
    assert missing_cross["evidence_complete"] is False
    assert missing_cross["unilateral_scope_authorized"] is False
    assert missing_cross["scope_verdict"] == "BLOCK_INCOMPLETE_EVIDENCE"

    incomplete_bilateral = module.assess(_payload(right_driver=None), "bilateral")
    assert incomplete_bilateral["evidence_complete"] is False
    assert incomplete_bilateral["scope_verdict"] == "ALLOW_QA_SCOPE_INCOMPLETE_EVIDENCE"
    assert incomplete_bilateral["runtime_authorized"] is False

    print("CIV1_BILATERAL_PATCH_SCOPE_TEST_OK")


if __name__ == "__main__":
    main()
