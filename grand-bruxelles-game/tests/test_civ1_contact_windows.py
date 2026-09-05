from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "tools" / "analyze_civ1_contact_windows.py"
spec = importlib.util.spec_from_file_location("civ1_contact_windows", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def _frame(index: int, right_y: float, left_y: float, right_x: float = 0.0, left_x: float = 0.0) -> dict:
    return {"sample_index": index, "poses": {"RightFoot": {"origin": [right_x, right_y, 0.0]}, "LeftFoot": {"origin": [left_x, left_y, 0.0]}}}


def test_cyclic_vertical_stability_merges_edge_window() -> None:
    frames = []
    for i in range(120):
        right_y = 1.0
        left_y = 1.0
        if i in {118, 119, 0, 1, 2}:
            right_y = 0.0
        if i in {20, 21, 22, 23}:
            left_y = [0.04, 0.0, 0.04, 0.09][i - 20]
        frames.append(_frame(i, right_y, left_y, right_x=i * 0.001, left_x=i * 0.002))

    right = module.analyze_foot(frames, "RightFoot")
    assert right["vertical_velocity_metric"] == "cyclic_central_difference_m_per_sample"
    assert right["hysteresis_exit_multiplier"] == 2.0
    assert right["eligible_vertical_stability_window_count"] >= 1
    assert any(window["wraps_cycle"] for window in right["windows"])


def test_transient_low_sweep_is_not_promoted_to_stable_contact() -> None:
    frames = []
    for i in range(120):
        left_y = 1.0
        if i == 19:
            left_y = 0.08
        elif i == 20:
            left_y = 0.02
        elif i == 21:
            left_y = 0.03
        elif i == 22:
            left_y = 0.09
        frames.append(_frame(i, 1.0, left_y, left_x=i * 0.05))

    left = module.analyze_foot(frames, "LeftFoot")
    assert left["low_sample_count"] >= 3
    assert all(not window["eligible_vertical_stability_window"] for window in left["windows"])


def test_bundle_contract_remains_fail_closed() -> None:
    frames = [_frame(i, 0.0 if 10 <= i <= 12 else 1.0, 0.0 if 50 <= i <= 52 else 1.0) for i in range(120)]
    bundle = {"schema": module.BUNDLE_SCHEMA, "runtime_authorized": False, "visual_approval_claimed": False, "player_view_claimed": False, "frames": frames}
    result = module.analyze_bundle(bundle)
    assert result["schema"] == module.SCHEMA
    assert result["ground_contact_claimed"] is False
    assert result["runtime_authorized"] is False
    assert result["visual_approval_claimed"] is False
    assert result["player_view_claimed"] is False
    assert result["verdict"] == "AMELIORER_VERTICAL_STABILITY_CLASSIFIED_GROUND_CONTACT_UNPROVEN"
    assert "planted" not in str(result).lower()

    bad = dict(bundle)
    bad["runtime_authorized"] = True
    try:
        module.analyze_bundle(bad)
    except ValueError as exc:
        assert "production rail" in str(exc)
    else:
        raise AssertionError("production authorization must be rejected")


if __name__ == "__main__":
    test_cyclic_vertical_stability_merges_edge_window()
    test_transient_low_sweep_is_not_promoted_to_stable_contact()
    test_bundle_contract_remains_fail_closed()
    print("CIV1_CONTACT_WINDOWS_TESTS_OK")
