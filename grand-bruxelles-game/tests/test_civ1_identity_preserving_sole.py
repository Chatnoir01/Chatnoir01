#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
TOOL = HERE / "tools" / "analyze_civ1_identity_preserving_sole.py"
spec = importlib.util.spec_from_file_location("identity_sole", TOOL)
assert spec and spec.loader
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def comp(lo, hi, center, pixels=20):
    return {"min_x_px": lo, "max_x_px": hi, "centroid_x_px": center, "pixel_count": pixels}


def main() -> int:
    chosen = m.choose_component([comp(90, 110, 100, 12), comp(200, 260, 230, 100)], 101.0)
    assert chosen["centroid_x_px"] == 100

    chosen = m.choose_component([comp(103, 111, 107, 10), comp(150, 190, 170, 80)], 105.0)
    assert chosen["centroid_x_px"] == 107

    try:
        m.choose_component([comp(140, 150, 145, 20)], 100.0)
    except ValueError as exc:
        assert "jump exceeds bound" in str(exc)
    else:
        raise AssertionError("large identity jump must fail closed")

    assert m._direction_match(-3.0, -2.5)
    assert m._direction_match(2.0, 1.0)
    assert not m._direction_match(-3.0, 2.5)
    assert not m._direction_match(0.1, 0.1)

    text = TOOL.read_text(encoding="utf-8")
    for key in (
        '"perceptual_2_8m_claimed": False',
        '"planted_contact_claimed": False',
        '"animation_correction_authorized": False',
        '"runtime_authorized": False',
        '"visual_approval_claimed": False',
        '"player_view_claimed": False',
    ):
        assert key in text
    compact = text.replace(" ", "")
    assert "MAX_TRACK_JUMP_PX=12.0" in compact
    assert '"required_distances_m":[2,4]' in compact
    assert '"qualified_8m_recovery":qualified_8m' in compact
    print("CIV1_IDENTITY_PRESERVING_SOLE_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
