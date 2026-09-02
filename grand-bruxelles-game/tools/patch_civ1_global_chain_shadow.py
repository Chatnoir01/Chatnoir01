#!/usr/bin/env python3
"""Transform the pinned historical CIV-1 retarget probe without mutating the skinned target.

The transformer is intentionally fail-closed: it accepts the exact historical ownership
block and exact RightFoot diagnostic anchors only. It also adds the missing symmetric
LeftFoot rest-direction counterfactual while preserving the historical RightFoot result.
"""
from __future__ import annotations

import argparse
from pathlib import Path

HELPER_ANCHOR = "func _write_payload(payload: Dictionary) -> bool:\n"
HELPER = '''func _make_shadow_skeleton(original: Skeleton3D) -> Skeleton3D:\n    var shadow := Skeleton3D.new()\n    shadow.name = \"CIV1DiagnosticShadowSkeleton\"\n    for i in range(original.get_bone_count()):\n        shadow.add_bone(original.get_bone_name(i))\n    for i in range(original.get_bone_count()):\n        shadow.set_bone_parent(i, original.get_bone_parent(i))\n        shadow.set_bone_rest(i, original.get_bone_rest(i))\n        shadow.set_bone_pose_position(i, original.get_bone_pose_position(i))\n        shadow.set_bone_pose_rotation(i, original.get_bone_pose_rotation(i))\n        shadow.set_bone_pose_scale(i, original.get_bone_pose_scale(i))\n    return shadow\n\n'''

LEFT_REFERENCE_HELPER = '''func _reference_ab_summary_for_foot(\n    foot_semantic: String,\n    phase_vertical_summary: Dictionary,\n    normalized_target_y: Array[float],\n    source_reference_direction_global: Vector3,\n    target_local_rest_origin: Vector3,\n    normalized_target_local_rest_origin: Vector3,\n    animation_length: float,\n) -> Dictionary:\n    var cycle_samples: int = SAMPLE_COUNT - 1\n    var source_min_index: int = int(phase_vertical_summary[\"per_bone\"][foot_semantic][\"source_vertical_min_sample_index\"])\n    var baseline_target_min_index: int = int(phase_vertical_summary[\"per_bone\"][foot_semantic][\"target_vertical_min_sample_index\"])\n    var normalized_target_min_index: int = -1\n    var normalized_min_y: float = INF\n    for sample_index in range(cycle_samples):\n        var y: float = normalized_target_y[sample_index]\n        if y < normalized_min_y:\n            normalized_min_y = y\n            normalized_target_min_index = sample_index\n    var baseline_phase_delta_samples: int = _signed_circular_delta(baseline_target_min_index, source_min_index, cycle_samples)\n    var normalized_phase_delta_samples: int = _signed_circular_delta(normalized_target_min_index, source_min_index, cycle_samples)\n    var baseline_phase_delta_seconds: float = float(baseline_phase_delta_samples) * animation_length / float(cycle_samples)\n    var normalized_phase_delta_seconds: float = float(normalized_phase_delta_samples) * animation_length / float(cycle_samples)\n    var baseline_abs: int = abs(baseline_phase_delta_samples)\n    var normalized_abs: int = abs(normalized_phase_delta_samples)\n    return {\n        \"method\": \"source_global_reference_direction_preserve_target_foot_length\",\n        \"source_reference_direction_global\": _v3(source_reference_direction_global),\n        \"target_local_rest_origin\": _v3(target_local_rest_origin),\n        \"normalized_target_local_rest_origin\": _v3(normalized_target_local_rest_origin),\n        \"target_foot_length_m\": target_local_rest_origin.length(),\n        \"normalized_target_foot_length_m\": normalized_target_local_rest_origin.length(),\n        \"target_foot_length_preserved\": is_equal_approx(target_local_rest_origin.length(), normalized_target_local_rest_origin.length()),\n        \"source_vertical_min_sample_index\": source_min_index,\n        \"baseline_target_vertical_min_sample_index\": baseline_target_min_index,\n        \"normalized_target_vertical_min_sample_index\": normalized_target_min_index,\n        \"baseline_phase_delta_samples\": baseline_phase_delta_samples,\n        \"normalized_phase_delta_samples\": normalized_phase_delta_samples,\n        \"baseline_phase_delta_seconds\": baseline_phase_delta_seconds,\n        \"normalized_phase_delta_seconds\": normalized_phase_delta_seconds,\n        \"normalization_improves_phase\": normalized_abs < baseline_abs,\n        \"normalization_reaches_non_material_phase\": normalized_abs <= PHASE_DIVERGENCE_MATERIAL_SAMPLES,\n        \"counterfactual_only\": true,\n    }\n\n'''

OLD_BLOCK = '''    var target_skeleton := target_skeletons[0]\n    var source_map := _mapping(source_skeleton)\n    var target_map := _mapping(target_skeleton)\n    if source_map.size() != SEMANTICS.size() or target_map.size() != SEMANTICS.size():\n        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: semantic mapping incomplete\")\n        quit(7)\n        return\n\n    var source_names := {}\n    for semantic in SEMANTICS:\n        source_names[semantic] = source_skeleton.get_bone_name(int(source_map[semantic]))\n    for semantic in SEMANTICS:\n        target_skeleton.set_bone_name(int(target_map[semantic]), StringName(\"GB_TMP_\" + semantic))\n    for semantic in SEMANTICS:\n        target_skeleton.set_bone_name(int(target_map[semantic]), StringName(source_names[semantic]))\n'''

NEW_BLOCK = '''    var original_target_skeleton := target_skeletons[0]\n    var source_map := _mapping(source_skeleton)\n    var original_target_map := _mapping(original_target_skeleton)\n    if source_map.size() != SEMANTICS.size() or original_target_map.size() != SEMANTICS.size():\n        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: semantic mapping incomplete\")\n        quit(7)\n        return\n\n    # Retarget a skeleton-only diagnostic twin. The imported CIV-1 Skeleton3D remains\n    # untouched so its three Skins keep their original named-bind contract.\n    var target_skeleton := _make_shadow_skeleton(original_target_skeleton)\n    root.add_child(target_skeleton)\n    target_skeleton.global_transform = original_target_skeleton.global_transform\n    var target_map := _mapping(target_skeleton)\n    if target_map.size() != SEMANTICS.size():\n        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: shadow semantic mapping incomplete\")\n        quit(7)\n        return\n\n\n    var source_names := {}\n    for semantic in SEMANTICS:\n        source_names[semantic] = source_skeleton.get_bone_name(int(source_map[semantic]))\n    for semantic in SEMANTICS:\n        target_skeleton.set_bone_name(int(target_map[semantic]), StringName(\"GB_TMP_\" + semantic))\n    for semantic in SEMANTICS:\n        target_skeleton.set_bone_name(int(target_map[semantic]), StringName(source_names[semantic]))\n'''

INDEX_ANCHOR = '''    var source_right_lower_idx := int(source_map[\"RightLowerLeg\"])\n    var source_right_foot_idx := int(source_map[\"RightFoot\"])\n    var target_right_lower_idx := int(target_map[\"RightLowerLeg\"])\n    var target_right_foot_idx := int(target_map[\"RightFoot\"])\n'''
LEFT_INDEX_BLOCK = '''    var source_left_lower_idx := int(source_map[\"LeftLowerLeg\"])\n    var source_left_foot_idx := int(source_map[\"LeftFoot\"])\n    var target_left_lower_idx := int(target_map[\"LeftLowerLeg\"])\n    var target_left_foot_idx := int(target_map[\"LeftFoot\"])\n'''

RIGHT_REST_TAIL = '''    var normalized_target_local_direction := (target_parent_rest.basis.inverse() * source_reference_direction_global).normalized()\n    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n'''
LEFT_REST_BLOCK = '''\n    var source_left_parent_rest := source_skeleton.get_bone_global_rest(source_left_lower_idx)\n    var source_left_foot_rest := source_skeleton.get_bone_global_rest(source_left_foot_idx)\n    var source_left_reference_vector_global := source_left_foot_rest.origin - source_left_parent_rest.origin\n    if source_left_reference_vector_global.length() <= 0.000001:\n        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: source LeftFoot reference vector is degenerate\")\n        quit(12)\n        return\n    var source_left_reference_direction_global := source_left_reference_vector_global.normalized()\n    var target_left_parent_rest := target_skeleton.get_bone_global_rest(target_left_lower_idx)\n    var target_left_local_rest_origin := target_skeleton.get_bone_rest(target_left_foot_idx).origin\n    if target_left_local_rest_origin.length() <= 0.000001:\n        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: target LeftFoot rest length is degenerate\")\n        quit(13)\n        return\n    var normalized_target_left_local_direction := (target_left_parent_rest.basis.inverse() * source_left_reference_direction_global).normalized()\n    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n'''

ARRAY_ANCHOR = "    var normalized_target_right_foot_y: Array[float] = []\n"
LEFT_ARRAY = "    var normalized_target_left_foot_y: Array[float] = []\n"

SAMPLE_ANCHOR = '''        normalized_target_right_foot_y.append(normalized_hips_relative.y)\n        model_space_samples.append({\"sample_index\": sample_idx, \"time_s\": t, \"bones\": bones})\n'''
SAMPLE_REPLACEMENT = '''        normalized_target_right_foot_y.append(normalized_hips_relative.y)\n        var target_left_parent_pose := target_skeleton.get_bone_global_pose(target_left_lower_idx)\n        var normalized_target_left_foot_origin := target_left_parent_pose.origin + target_left_parent_pose.basis * normalized_target_left_local_rest_origin\n        var normalized_left_hips_relative := normalized_target_left_foot_origin - target_hips_pose.origin\n        normalized_target_left_foot_y.append(normalized_left_hips_relative.y)\n        model_space_samples.append({\"sample_index\": sample_idx, \"time_s\": t, \"bones\": bones})\n'''

SUMMARY_ANCHOR = '''    var right_foot_reference_ab := _reference_ab_summary(\n        phase_vertical_summary,\n        normalized_target_right_foot_y,\n        source_reference_direction_global,\n        target_local_rest_origin,\n        normalized_target_local_rest_origin,\n        animation.length,\n    )\n'''
LEFT_SUMMARY = '''    var left_foot_reference_ab := _reference_ab_summary_for_foot(\n        \"LeftFoot\",\n        phase_vertical_summary,\n        normalized_target_left_foot_y,\n        source_left_reference_direction_global,\n        target_left_local_rest_origin,\n        normalized_target_left_local_rest_origin,\n        animation.length,\n    )\n'''
PAYLOAD_ANCHOR = '        "right_foot_reference_ab": right_foot_reference_ab,\n'
LEFT_PAYLOAD = '        "left_foot_reference_ab": left_foot_reference_ab,\n'


def _replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise ValueError(f"expected exactly one {label} anchor")
    return text.replace(old, new, 1)


def transform(text: str) -> str:
    if text.count(HELPER_ANCHOR) != 1:
        raise ValueError("expected exactly one helper anchor")
    if text.count(OLD_BLOCK) != 1:
        raise ValueError("historical target-renaming block drifted; refusing partial patch")
    if "func _make_shadow_skeleton" in text or "left_foot_reference_ab" in text:
        raise ValueError("input already contains shadow/bilateral helper")

    text = text.replace(HELPER_ANCHOR, HELPER + LEFT_REFERENCE_HELPER + HELPER_ANCHOR, 1)
    text = text.replace(OLD_BLOCK, NEW_BLOCK, 1)
    text = _replace_once(text, INDEX_ANCHOR, LEFT_INDEX_BLOCK + INDEX_ANCHOR, "foot-index")
    text = _replace_once(text, RIGHT_REST_TAIL, RIGHT_REST_TAIL + LEFT_REST_BLOCK, "right-rest-tail")
    text = _replace_once(text, ARRAY_ANCHOR, ARRAY_ANCHOR + LEFT_ARRAY, "sample-array")
    text = _replace_once(text, SAMPLE_ANCHOR, SAMPLE_REPLACEMENT, "sample")
    text = _replace_once(text, SUMMARY_ANCHOR, SUMMARY_ANCHOR + LEFT_SUMMARY, "summary")
    text = _replace_once(text, PAYLOAD_ANCHOR, PAYLOAD_ANCHOR + LEFT_PAYLOAD, "payload")

    if "original_target_skeleton.set_bone_name" in text:
        raise ValueError("skinned target rename survived transform")
    return text


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    source = args.input.read_text(encoding="utf-8")
    patched = transform(source)
    args.output.write_text(patched, encoding="utf-8")
    print("CIV1_SHADOW_BILATERAL_RETARGET_PATCH_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
