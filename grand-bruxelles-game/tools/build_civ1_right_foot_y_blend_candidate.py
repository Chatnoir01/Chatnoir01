#!/usr/bin/env python3
from pathlib import Path
import sys

OLD_LINE = "var target_right_foot_normalized_local_rest_origin := normalized_local_direction * target_right_foot_original_local_rest_origin.length()"
METHOD_OLD = '"reference_normalization_method": "source_global_reference_direction_preserve_target_foot_length"'
FORMAT_OLD = '"grand-bruxelles-civ1-right-foot-reference-ab-v2"'
LENGTH_FIELD = '"target_right_foot_length_preserved": length_preserved,'


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: build_civ1_right_foot_y_blend_candidate.py <input.gd> <output.gd> <blend_alpha>", file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    blend_alpha = float(sys.argv[3])
    if not 0.0 <= blend_alpha <= 1.0:
        raise SystemExit("blend_alpha must be within [0,1]")

    text = src.read_text(encoding="utf-8")
    for token in (OLD_LINE, METHOD_OLD, FORMAT_OLD, LENGTH_FIELD):
        count = text.count(token)
        if count != 1:
            raise SystemExit(f"candidate source drift: expected exactly one token, got {count}: {token}")

    alpha_literal = f"{blend_alpha:.6f}"
    new_block = f'''var target_length := target_right_foot_original_local_rest_origin.length()
    var blend_alpha := {alpha_literal}
    var full_y := normalized_local_direction.y * target_length
    var original_y := target_right_foot_original_local_rest_origin.y
    var blended_y := lerpf(full_y, original_y, blend_alpha)
    if absf(blended_y) > target_length:
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: blended Y exceeds target foot length")
        quit(14)
        return
    var source_horizontal := Vector2(normalized_local_direction.x, normalized_local_direction.z)
    if source_horizontal.length() <= 0.000001:
        push_error("CIV1_RIGHT_FOOT_REFERENCE_AB_FAIL: source XZ direction degenerate")
        quit(15)
        return
    source_horizontal = source_horizontal.normalized()
    var horizontal_length := sqrt(maxf((target_length * target_length) - (blended_y * blended_y), 0.0))
    var target_right_foot_normalized_local_rest_origin := Vector3(source_horizontal.x * horizontal_length, blended_y, source_horizontal.y * horizontal_length)'''

    text = text.replace(OLD_LINE, new_block, 1)
    text = text.replace(FORMAT_OLD, '"grand-bruxelles-civ1-right-foot-reference-ab-v4"', 1)
    text = text.replace(METHOD_OLD, '"reference_normalization_method": "source_global_reference_direction_y_blend_preserve_target_length"', 1)
    text = text.replace(
        LENGTH_FIELD,
        LENGTH_FIELD + f'\n        "target_right_foot_y_blend_alpha": {alpha_literal},',
        1,
    )

    required = (
        "source_global_reference_direction_y_blend_preserve_target_length",
        "blend_alpha",
        "full_y",
        "original_y",
        "horizontal_length",
        "target_right_foot_length_preserved",
        "target_right_foot_y_blend_alpha",
        "grand-bruxelles-civ1-right-foot-reference-ab-v4",
    )
    for token in required:
        if token not in text:
            raise SystemExit(f"candidate build missing token: {token}")

    dst.write_text(text, encoding="utf-8")
    print(f"CIV1_RIGHT_FOOT_Y_BLEND_CANDIDATE_BUILT alpha={blend_alpha:.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
