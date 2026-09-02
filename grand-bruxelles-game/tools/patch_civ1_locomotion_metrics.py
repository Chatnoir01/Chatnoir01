#!/usr/bin/env python3
"""Extend the validated bilateral shadow CIV-1 probe with paired planted-foot metrics.

This transformer is QA-only and fail-closed. It does not change production runtime or the
counterfactual definition; it only records baseline/counterfactual foot positions on the
same five-sample source-plant window and emits horizontal drift + vertical span.
"""
from __future__ import annotations

import argparse
from pathlib import Path

HELPER_ANCHOR = "func _write_payload(payload: Dictionary) -> bool:\n"
HELPER = '''func _arr_v3(value: Array) -> Vector3:\n    if value.size() != 3:\n        return Vector3(INF, INF, INF)\n    return Vector3(float(value[0]), float(value[1]), float(value[2]))\n\nfunc _plant_window(center: int, cycle_samples: int) -> Array[int]:\n    var result: Array[int] = []\n    for offset in [-2, -1, 0, 1, 2]:\n        result.append(posmod(center + offset, cycle_samples))\n    return result\n\nfunc _motion_metrics(points: Array) -> Dictionary:\n    if points.size() < 3:\n        return {}\n    var first := _arr_v3(points[0])\n    if not first.is_finite():\n        return {}\n    var max_horizontal := 0.0\n    var min_y := first.y\n    var max_y := first.y\n    for raw in points:\n        var p := _arr_v3(raw)\n        if not p.is_finite():\n            return {}\n        var horizontal := Vector2(p.x, p.z).distance_to(Vector2(first.x, first.z))\n        max_horizontal = max(max_horizontal, horizontal)\n        min_y = min(min_y, p.y)\n        max_y = max(max_y, p.y)\n    return {\n        \"planted_sample_count\": points.size(),\n        \"planted_horizontal_drift_m\": max_horizontal,\n        \"planted_vertical_span_m\": max_y - min_y,\n    }\n\nfunc _foot_locomotion_pair(\n    foot_semantic: String,\n    model_space_samples: Array[Dictionary],\n    normalized_target_xyz: Array,\n    phase_vertical_summary: Dictionary,\n) -> Dictionary:\n    var cycle_samples: int = SAMPLE_COUNT - 1\n    if normalized_target_xyz.size() < cycle_samples:\n        return {}\n    var center := int(phase_vertical_summary[\"per_bone\"][foot_semantic][\"source_vertical_min_sample_index\"])\n    var indices := _plant_window(center, cycle_samples)\n    var baseline: Array = []\n    var counterfactual: Array = []\n    for sample_index in indices:\n        baseline.append(model_space_samples[sample_index][\"bones\"][foot_semantic][\"target\"][\"target_hips_relative_origin\"])\n        counterfactual.append(normalized_target_xyz[sample_index])\n    return {\n        \"plant_window_source_min_sample_index\": center,\n        \"plant_window_sample_indices\": indices,\n        \"same_animation_window\": true,\n        \"baseline\": _motion_metrics(baseline),\n        \"counterfactual\": _motion_metrics(counterfactual),\n    }\n\n'''

ARRAY_ANCHOR = '''    var normalized_target_right_foot_y: Array[float] = []\n    var normalized_target_left_foot_y: Array[float] = []\n'''
ARRAY_REPLACEMENT = ARRAY_ANCHOR + '''    var normalized_target_right_foot_xyz: Array = []\n    var normalized_target_left_foot_xyz: Array = []\n'''

RIGHT_SAMPLE = "        normalized_target_right_foot_y.append(normalized_hips_relative.y)\n"
RIGHT_SAMPLE_REPLACEMENT = RIGHT_SAMPLE + "        normalized_target_right_foot_xyz.append(_v3(normalized_hips_relative))\n"
LEFT_SAMPLE = "        normalized_target_left_foot_y.append(normalized_left_hips_relative.y)\n"
LEFT_SAMPLE_REPLACEMENT = LEFT_SAMPLE + "        normalized_target_left_foot_xyz.append(_v3(normalized_left_hips_relative))\n"

SUMMARY_ANCHOR = '''    var left_foot_reference_ab := _reference_ab_summary_for_foot(\n        \"LeftFoot\",\n        phase_vertical_summary,\n        normalized_target_left_foot_y,\n        source_left_reference_direction_global,\n        target_left_local_rest_origin,\n        normalized_target_left_local_rest_origin,\n        animation.length,\n    )\n'''
SUMMARY_APPEND = SUMMARY_ANCHOR + '''    var locomotion_measurements := {\n        \"method\": \"five_sample_source_vertical_min_window\",\n        \"LeftFoot\": _foot_locomotion_pair(\"LeftFoot\", model_space_samples, normalized_target_left_foot_xyz, phase_vertical_summary),\n        \"RightFoot\": _foot_locomotion_pair(\"RightFoot\", model_space_samples, normalized_target_right_foot_xyz, phase_vertical_summary),\n    }\n'''
PAYLOAD_ANCHOR = '        "left_foot_reference_ab": left_foot_reference_ab,\n'
PAYLOAD_REPLACEMENT = PAYLOAD_ANCHOR + '        "locomotion_measurements": locomotion_measurements,\n'


def _replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"expected exactly one {label} anchor, got {count}")
    return text.replace(old, new, 1)


def transform(text: str) -> str:
    if "func _foot_locomotion_pair" in text or '"locomotion_measurements"' in text:
        raise ValueError("input already contains locomotion metrics")
    if "func _make_shadow_skeleton" not in text or "left_foot_reference_ab" not in text:
        raise ValueError("input is not the validated bilateral shadow probe")
    text = _replace_once(text, HELPER_ANCHOR, HELPER + HELPER_ANCHOR, "helper")
    text = _replace_once(text, ARRAY_ANCHOR, ARRAY_REPLACEMENT, "normalized-array")
    text = _replace_once(text, RIGHT_SAMPLE, RIGHT_SAMPLE_REPLACEMENT, "right-sample")
    text = _replace_once(text, LEFT_SAMPLE, LEFT_SAMPLE_REPLACEMENT, "left-sample")
    text = _replace_once(text, SUMMARY_ANCHOR, SUMMARY_APPEND, "summary")
    text = _replace_once(text, PAYLOAD_ANCHOR, PAYLOAD_REPLACEMENT, "payload")
    return text


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    patched = transform(args.input.read_text(encoding="utf-8"))
    args.output.write_text(patched, encoding="utf-8")
    print("CIV1_LOCOMOTION_METRICS_PATCH_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
