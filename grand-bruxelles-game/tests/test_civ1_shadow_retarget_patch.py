#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "patch_civ1_global_chain_shadow.py"
spec = importlib.util.spec_from_file_location("shadow_patch", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def fixture() -> str:
    return (
        "extends SceneTree\n\n"
        + module.HELPER_ANCHOR
        + "    return true\n\nfunc _run() -> void:\n"
        + module.OLD_BLOCK
        + "\n"
        + module.INDEX_ANCHOR
        + "\n"
        + module.RIGHT_REST_TAIL
        + "\n"
        + module.ARRAY_ANCHOR
        + "\n"
        + module.SAMPLE_ANCHOR
        + "\n"
        + module.SUMMARY_ANCHOR
        + "    var payload := {\n"
        + module.PAYLOAD_ANCHOR
        + "    }\n"
    )


def main() -> int:
    patched = module.transform(fixture())
    assert patched.count("func _make_shadow_skeleton") == 1
    assert patched.count("func _reference_ab_summary_for_foot") == 1
    assert "var original_target_skeleton := target_skeletons[0]" in patched
    assert "var target_skeleton := _make_shadow_skeleton(original_target_skeleton)" in patched
    assert "target_skeleton.global_transform = original_target_skeleton.global_transform" in patched
    assert "original_target_skeleton.set_bone_name" not in patched
    assert patched.count("target_skeleton.set_bone_name") == 2
    assert 'var source_left_lower_idx := int(source_map["LeftLowerLeg"])' in patched
    assert 'var source_left_foot_idx := int(source_map["LeftFoot"])' in patched
    assert "normalized_target_left_foot_y.append" in patched
    assert 'var left_foot_reference_ab := _reference_ab_summary_for_foot(' in patched
    assert '"LeftFoot",' in patched
    assert '"left_foot_reference_ab": left_foot_reference_ab,' in patched
    assert patched.count('"right_foot_reference_ab": right_foot_reference_ab,') == 1

    try:
        module.transform(fixture().replace("semantic mapping incomplete", "semantic map changed", 1))
    except ValueError as exc:
        assert "drifted" in str(exc)
    else:
        raise AssertionError("drifted historical block was not rejected")

    try:
        module.transform(fixture().replace(module.SAMPLE_ANCHOR, module.SAMPLE_ANCHOR + module.SAMPLE_ANCHOR))
    except ValueError as exc:
        assert "sample" in str(exc)
    else:
        raise AssertionError("ambiguous sample anchor was not rejected")

    try:
        module.transform(fixture() + "\n" + module.HELPER_ANCHOR)
    except ValueError as exc:
        assert "helper anchor" in str(exc)
    else:
        raise AssertionError("ambiguous helper anchor was not rejected")

    print("CIV1_SHADOW_BILATERAL_RETARGET_PATCH_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
