#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "patch_civ1_locomotion_metrics.py"
spec = importlib.util.spec_from_file_location("patcher", TOOL)
patcher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(patcher)


def fixture() -> str:
    return '''func _make_shadow_skeleton(original: Skeleton3D) -> Skeleton3D:\n    return Skeleton3D.new()\n\nfunc _reference_ab_summary_for_foot():\n    pass\n\nfunc _write_payload(payload: Dictionary) -> bool:\n    return true\n\nfunc _run() -> void:\n    var normalized_target_right_foot_y: Array[float] = []\n    var normalized_target_left_foot_y: Array[float] = []\n    normalized_target_right_foot_y.append(normalized_hips_relative.y)\n    normalized_target_left_foot_y.append(normalized_left_hips_relative.y)\n    var left_foot_reference_ab := _reference_ab_summary_for_foot(\n        "LeftFoot",\n        phase_vertical_summary,\n        normalized_target_left_foot_y,\n        source_left_reference_direction_global,\n        target_left_local_rest_origin,\n        normalized_target_left_local_rest_origin,\n        animation.length,\n    )\n    var payload := {\n        "left_foot_reference_ab": left_foot_reference_ab,\n    }\n'''


def main() -> int:
    out = patcher.transform(fixture())
    assert '"method": "five_sample_source_vertical_min_window"' in out
    assert '"locomotion_measurements": locomotion_measurements' in out
    assert 'normalized_target_right_foot_xyz.append(_v3(normalized_hips_relative))' in out
    assert 'normalized_target_left_foot_xyz.append(_v3(normalized_left_hips_relative))' in out
    assert '"same_animation_window": true' in out
    assert 'for offset in [-2, -1, 0, 1, 2]' in out
    assert 'planted_horizontal_drift_m' in out
    assert 'planted_vertical_span_m' in out

    for broken in (
        fixture().replace('func _make_shadow_skeleton', 'func missing_shadow'),
        fixture().replace('left_foot_reference_ab', 'left_missing', 1),
        fixture().replace('normalized_target_right_foot_y.append(normalized_hips_relative.y)\n', ''),
    ):
        try:
            patcher.transform(broken)
        except ValueError:
            pass
        else:
            raise AssertionError("drifted/non-bilateral input must fail closed")

    try:
        patcher.transform(out)
    except ValueError:
        pass
    else:
        raise AssertionError("double transform must fail closed")

    print("CIV1_LOCOMOTION_METRICS_PATCH_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
