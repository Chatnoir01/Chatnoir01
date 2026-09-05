from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "tools" / "analyze_civ1_contact_windows.py"
spec = importlib.util.spec_from_file_location("civ1_contact_windows", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def _frame(index: int, right_y: float, left_y: float, right_x: float = 0.0, left_x: float = 0.0) -> dict:
    return {
        "sample_index": index,
        "poses": {
            "RightFoot": {"origin": [right_x, right_y, 0.0]},
            "LeftFoot": {"origin": [left_x, left_y, 0.0]},
        },
    }


def test_contact_windows_split_and_merge_cycle_edges() -> None:
    frames = []
    for i in range(120):
        right_y = 1.0
        left_y = 1.0
        if i in {118, 119, 0, 1, 2}:
            right_y = 0.0
        if i in {20, 21, 22, 40, 41, 42}:
            left_y = 0.0
        frames.append(_frame(i, right_y, left_y, right_x=i * 0.001, left_x=i * 0.002))

    right = module.analyze_foot(frames, "RightFoot")
    left = module.analyze_foot(frames, "LeftFoot")

    assert right["low_sample_count"] == 5
    assert right["window_count"] == 1
    window = right["windows"][0]
    assert window["wraps_cycle"] is True
    assert window["sample_indices"] == [118, 119, 0, 1, 2]
    assert window["eligible_planted_window"] is True

    assert left["low_sample_count"] == 6
    assert left["window_count"] == 2
    assert [w["sample_indices"] for w in left["windows"]] == [[20, 21, 22], [40, 41, 42]]
    assert left["eligible_window_count"] == 2


def test_bundle_contract_is_fail_closed_and_never_claims_grounding() -> None:
    frames = [_frame(i, 0.0 if 10 <= i <= 12 else 1.0, 0.0 if 50 <= i <= 52 else 1.0) for i in range(120)]
    bundle = {
        "schema": module.BUNDLE_SCHEMA,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "frames": frames,
    }
    result = module.analyze_bundle(bundle)
    assert result["schema"] == module.SCHEMA
    assert result["diagnostic_only"] is True
    assert result["runtime_authorized"] is False
    assert result["visual_approval_claimed"] is False
    assert result["player_view_claimed"] is False
    assert result["verdict"] == "AMELIORER_CONTACT_WINDOWS_REQUIRE_GROUNDING_REVIEW"

    bad = dict(bundle)
    bad["runtime_authorized"] = True
    try:
        module.analyze_bundle(bad)
    except ValueError as exc:
        assert "production rail" in str(exc)
    else:
        raise AssertionError("production authorization must be rejected")


if __name__ == "__main__":
    test_contact_windows_split_and_merge_cycle_edges()
    test_bundle_contract_is_fail_closed_and_never_claims_grounding()
    print("CIV1_CONTACT_WINDOWS_TESTS_OK")
