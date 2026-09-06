#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
TOOL = HERE / "tools" / "analyze_civ1_same_row_gap_bridge.py"
spec = importlib.util.spec_from_file_location("same_row", TOOL)
assert spec and spec.loader
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def rec(sample, x, n, y=357):
    return {
        "sample_index": sample,
        "bottom_y_px": y,
        "bottom_centroid_x_px": float(x),
        "bottom_pixel_count": n,
        "measurement_resolved": n >= m.MIN_RESOLVED_PIXELS,
    }


def main() -> int:
    real_shape = [rec(115, 592.5, 20), rec(116, 593.0, 19), rec(117, 593.5, 20), rec(118, 594.5, 20)]
    ok, reasons = m.bridge_candidate(real_shape, 1)
    assert ok and reasons == []

    too_sparse = [rec(115, 592.5, 20), rec(116, 593.0, 8), rec(117, 593.5, 20)]
    ok, reasons = m.bridge_candidate(too_sparse, 1)
    assert not ok and "below_bridge_sampling_floor" in reasons

    wrong_row = [rec(115, 592.5, 20), rec(116, 593.0, 19, y=358), rec(117, 593.5, 20)]
    ok, reasons = m.bridge_candidate(wrong_row, 1)
    assert not ok and "bottom_row_changed" in reasons

    switched_semantic = [rec(115, 592.5, 20), rec(116, 610.0, 19), rec(117, 593.5, 20)]
    ok, reasons = m.bridge_candidate(switched_semantic, 1)
    assert not ok and "centroid_outside_bracket" in reasons

    text = TOOL.read_text(encoding="utf-8")
    assert "MIN_RESOLVED_PIXELS = 20" in text
    assert "MIN_BRIDGE_PIXELS = 15" in text
    assert "MAX_BRACKET_OVERSHOOT_PX = 1.0" in text
    assert "multi-row/component" in text
    for key in (
        '"perceptual_2_8m_claimed": False',
        '"planted_contact_claimed": False',
        '"animation_correction_authorized": False',
        '"runtime_authorized": False',
        '"visual_approval_claimed": False',
        '"player_view_claimed": False',
    ):
        assert key in text
    print("CIV1_SAME_ROW_GAP_BRIDGE_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
