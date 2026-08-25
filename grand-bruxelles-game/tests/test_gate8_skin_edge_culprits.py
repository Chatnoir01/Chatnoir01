#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "analyze_gate8_skin_edge_culprits.py"
spec = importlib.util.spec_from_file_location("gate8_edge_culprits", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


def _edge(a, b):
    return {
        "mesh": "mesh",
        "surface": 0,
        "triangle": 1,
        "vertex_a": 10,
        "vertex_b": 11,
        "rest_length_m": 0.1,
        "posed_length_m": 0.5,
        "absolute_change_m": 0.4,
        "ratio": 5.0,
        "vertex_a_weights": a,
        "vertex_b_weights": b,
    }


def test_weight_discontinuity_dominant_pair():
    edge = _edge(
        [
            {"bone_name": "arm", "weight": 0.95},
            {"bone_name": "spine", "weight": 0.05},
        ],
        [
            {"bone_name": "arm", "weight": 0.05},
            {"bone_name": "spine", "weight": 0.90},
            {"bone_name": "chest", "weight": 0.05},
        ],
    )
    row = module.analyze_edge(edge)
    assert set(row["dominant_pair"]) == {"arm", "spine"}
    assert row["dominant_pair_share"] > 0.97
    assert row["weight_discontinuity_total"] > 1.7


def test_zero_discontinuity_is_rejected():
    edge = _edge(
        [{"bone_name": "foot", "weight": 1.0}],
        [{"bone_name": "foot", "weight": 1.0}],
    )
    try:
        module.analyze_edge(edge)
    except ValueError as exc:
        assert "no measurable endpoint weight discontinuity" in str(exc)
    else:
        raise AssertionError("expected zero-discontinuity edge to be rejected")


def test_known_walk_formal_pairs_remain_localized():
    cases = {
        "left_armpit": _edge(
            [
                {"bone_name": "DEF-upper_arm.L", "weight": 0.950713336467743},
                {"bone_name": "DEF-spine.003", "weight": 0.0309758149087429},
                {"bone_name": "DEF-shoulder.L", "weight": 0.0182803086936474},
            ],
            [
                {"bone_name": "DEF-spine.003", "weight": 0.844556331634521},
                {"bone_name": "DEF-spine.002", "weight": 0.0820172429084778},
                {"bone_name": "DEF-upper_arm.L", "weight": 0.0716411098837852},
                {"bone_name": "DEF-spine.001", "weight": 0.00175478751771152},
            ],
        ),
        "right_armpit": _edge(
            [
                {"bone_name": "DEF-spine.003", "weight": 0.715632855892181},
                {"bone_name": "DEF-upper_arm.R", "weight": 0.253284513950348},
                {"bone_name": "DEF-shoulder.R", "weight": 0.017624169588089},
                {"bone_name": "DEF-spine.002", "weight": 0.0134279392659664},
            ],
            [
                {"bone_name": "DEF-upper_arm.R", "weight": 0.78739607334137},
                {"bone_name": "DEF-spine.003", "weight": 0.131517514586449},
                {"bone_name": "DEF-shoulder.R", "weight": 0.0810559242963791},
            ],
        ),
        "left_ankle": _edge(
            [
                {"bone_name": "DEF-foot.L", "weight": 0.741008639335632},
                {"bone_name": "DEF-shin.L", "weight": 0.258976131677628},
            ],
            [
                {"bone_name": "DEF-foot.L", "weight": 0.909193575382233},
                {"bone_name": "DEF-shin.L", "weight": 0.090791180729866},
            ],
        ),
    }
    expected = {
        "left_armpit": {"DEF-upper_arm.L", "DEF-spine.003"},
        "right_armpit": {"DEF-upper_arm.R", "DEF-spine.003"},
        "left_ankle": {"DEF-foot.L", "DEF-shin.L"},
    }
    for name, edge in cases.items():
        row = module.analyze_edge(edge)
        assert set(row["dominant_pair"]) == expected[name]
        assert row["dominant_pair_share"] >= 0.90


if __name__ == "__main__":
    test_weight_discontinuity_dominant_pair()
    test_zero_discontinuity_is_rejected()
    test_known_walk_formal_pairs_remain_localized()
    print("GATE8_SKIN_EDGE_CULPRIT_TESTS_OK")
