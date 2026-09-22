#!/usr/bin/env python3
from pathlib import Path
import sys

ANCHOR = '    var source_right_lower_idx := int(source_map["RightLowerLeg"])\n'
LENGTH_FIELD = '        "target_right_foot_length_preserved": length_preserved,\n'
SUPPORTED_FORMATS = (
    '"grand-bruxelles-civ1-right-foot-reference-ab-v2"',
    '"grand-bruxelles-civ1-right-foot-reference-ab-v4"',
)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: build_civ1_upperleg_lowerleg_z_candidate.py <input.gd> <output.gd>", file=sys.stderr)
        return 2

    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    text = src.read_text(encoding="utf-8")

    for token in (ANCHOR, LENGTH_FIELD):
        count = text.count(token)
        if count != 1:
            raise SystemExit(f"candidate source drift: expected exactly one token, got {count}: {token}")
    present_formats = [token for token in SUPPORTED_FORMATS if text.count(token) == 1]
    if len(present_formats) != 1:
        raise SystemExit(f"candidate source drift: expected exactly one supported reference format, got {present_formats}")

    block = '''    # Diagnostic-only axis-z UpperLeg->LowerLeg rest-basis candidate.
    # Reconstruct the source child-rest direction in each target parent-rest
    # basis, replace only Z, then renormalize to the exact target bone length.
    var upperleg_lowerleg_z_candidate_applied := true
    var upperleg_lowerleg_z_lengths_preserved := true
    for side_semantics in [["LeftUpperLeg", "LeftLowerLeg"], ["RightUpperLeg", "RightLowerLeg"]]:
        var parent_semantic: String = side_semantics[0]
        var child_semantic: String = side_semantics[1]
        var source_parent_idx := int(source_map[parent_semantic])
        var source_child_idx := int(source_map[child_semantic])
        var target_parent_idx := int(target_map[parent_semantic])
        var target_child_idx := int(target_map[child_semantic])
        var source_local_rest := source_skeleton.get_bone_rest(source_child_idx).origin
        var target_rest := target_skeleton.get_bone_rest(target_child_idx)
        var target_local_rest := target_rest.origin
        var target_length := target_local_rest.length()
        if source_local_rest.length() <= 0.000001 or target_length <= 0.000001:
            push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: degenerate UpperLeg->LowerLeg rest vector")
            quit(16)
            return
        var source_parent_global_rest := source_skeleton.get_bone_global_rest(source_parent_idx)
        var target_parent_global_rest := target_skeleton.get_bone_global_rest(target_parent_idx)
        var source_world_rest := source_parent_global_rest.basis * source_local_rest
        var source_rest_in_target_parent_basis := target_parent_global_rest.basis.inverse() * source_world_rest
        source_rest_in_target_parent_basis = source_rest_in_target_parent_basis.normalized() * target_length
        var candidate := target_local_rest
        candidate.z = source_rest_in_target_parent_basis.z
        if candidate.length() <= 0.000001:
            push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: degenerate axis-z candidate")
            quit(17)
            return
        candidate = candidate.normalized() * target_length
        var candidate_rest := target_rest
        candidate_rest.origin = candidate
        target_skeleton.set_bone_rest(target_child_idx, candidate_rest)
        target_skeleton.reset_bone_pose(target_child_idx)
        if absf(candidate.length() - target_length) > 0.000001:
            upperleg_lowerleg_z_lengths_preserved = false
    target_skeleton.force_update_all_bone_transforms()
    await process_frame

'''

    text = text.replace(ANCHOR, block + ANCHOR, 1)
    text = text.replace(
        LENGTH_FIELD,
        LENGTH_FIELD
        + '        "upperleg_lowerleg_z_candidate_applied": upperleg_lowerleg_z_candidate_applied,\n'
        + '        "upperleg_lowerleg_z_lengths_preserved": upperleg_lowerleg_z_lengths_preserved,\n'
        + '        "upperleg_lowerleg_rest_axis": "z",\n',
        1,
    )

    required = (
        "axis-z UpperLeg->LowerLeg",
        "source_rest_in_target_parent_basis",
        "candidate.z = source_rest_in_target_parent_basis.z",
        "candidate = candidate.normalized() * target_length",
        "target_skeleton.set_bone_rest(target_child_idx, candidate_rest)",
        "target_skeleton.reset_bone_pose(target_child_idx)",
        "upperleg_lowerleg_z_candidate_applied",
        "upperleg_lowerleg_z_lengths_preserved",
    )
    for token in required:
        if token not in text:
            raise SystemExit(f"candidate build missing token: {token}")

    dst.write_text(text, encoding="utf-8")
    print(f"CIV1_UPPERLEG_LOWERLEG_Z_CANDIDATE_BUILT axis=z bilateral target-length-preserving input_format={present_formats[0]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
