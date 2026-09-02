#!/usr/bin/env python3
"""Transform the pinned historical CIV-1 global-chain probe so retarget QA never renames the skinned target Skeleton3D in place.

The transformer is intentionally fail-closed: it only accepts the exact historical ownership block.
If upstream probe text drifts, no partially patched diagnostic is emitted.
"""
from __future__ import annotations

import argparse
from pathlib import Path

HELPER_ANCHOR = "func _write_payload(payload: Dictionary) -> bool:\n"
HELPER = '''func _make_shadow_skeleton(original: Skeleton3D) -> Skeleton3D:\n    var shadow := Skeleton3D.new()\n    shadow.name = \"CIV1DiagnosticShadowSkeleton\"\n    for i in range(original.get_bone_count()):\n        shadow.add_bone(original.get_bone_name(i))\n    for i in range(original.get_bone_count()):\n        shadow.set_bone_parent(i, original.get_bone_parent(i))\n        shadow.set_bone_rest(i, original.get_bone_rest(i))\n        shadow.set_bone_pose_position(i, original.get_bone_pose_position(i))\n        shadow.set_bone_pose_rotation(i, original.get_bone_pose_rotation(i))\n        shadow.set_bone_pose_scale(i, original.get_bone_pose_scale(i))\n    return shadow\n\n'''

OLD_BLOCK = '''    var target_skeleton := target_skeletons[0]\n    var source_map := _mapping(source_skeleton)\n    var target_map := _mapping(target_skeleton)\n    if source_map.size() != SEMANTICS.size() or target_map.size() != SEMANTICS.size():\n        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: semantic mapping incomplete\")\n        quit(7)\n        return\n\n    var source_names := {}\n    for semantic in SEMANTICS:\n        source_names[semantic] = source_skeleton.get_bone_name(int(source_map[semantic]))\n    for semantic in SEMANTICS:\n        target_skeleton.set_bone_name(int(target_map[semantic]), StringName(\"GB_TMP_\" + semantic))\n    for semantic in SEMANTICS:\n        target_skeleton.set_bone_name(int(target_map[semantic]), StringName(source_names[semantic]))\n'''

NEW_BLOCK = '''    var original_target_skeleton := target_skeletons[0]\n    var source_map := _mapping(source_skeleton)\n    var original_target_map := _mapping(original_target_skeleton)\n    if source_map.size() != SEMANTICS.size() or original_target_map.size() != SEMANTICS.size():\n        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: semantic mapping incomplete\")\n        quit(7)\n        return\n\n    # Retarget a skeleton-only diagnostic twin. The imported CIV-1 Skeleton3D remains\n    # untouched so its three Skins keep their original named-bind contract.\n    var target_skeleton := _make_shadow_skeleton(original_target_skeleton)\n    root.add_child(target_skeleton)\n    target_skeleton.global_transform = original_target_skeleton.global_transform\n    var target_map := _mapping(target_skeleton)\n    if target_map.size() != SEMANTICS.size():\n        push_error(\"CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: shadow semantic mapping incomplete\")\n        quit(7)\n        return\n\n\n    var source_names := {}\n    for semantic in SEMANTICS:\n        source_names[semantic] = source_skeleton.get_bone_name(int(source_map[semantic]))\n    for semantic in SEMANTICS:\n        target_skeleton.set_bone_name(int(target_map[semantic]), StringName(\"GB_TMP_\" + semantic))\n    for semantic in SEMANTICS:\n        target_skeleton.set_bone_name(int(target_map[semantic]), StringName(source_names[semantic]))\n'''


def transform(text: str) -> str:
    if text.count(HELPER_ANCHOR) != 1:
        raise ValueError("expected exactly one helper anchor")
    if text.count(OLD_BLOCK) != 1:
        raise ValueError("historical target-renaming block drifted; refusing partial patch")
    if "func _make_shadow_skeleton" in text:
        raise ValueError("input already contains shadow helper")
    text = text.replace(HELPER_ANCHOR, HELPER + HELPER_ANCHOR, 1)
    text = text.replace(OLD_BLOCK, NEW_BLOCK, 1)
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
    print("CIV1_SHADOW_RETARGET_PATCH_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
