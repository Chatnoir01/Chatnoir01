#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "patch_civ1_global_chain_shadow.py"
spec = importlib.util.spec_from_file_location("shadow_patch", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def fixture() -> str:
    return "extends SceneTree\n\n" + module.HELPER_ANCHOR + "    pass\n\nfunc _run() -> void:\n" + module.OLD_BLOCK + "\n"


def main() -> int:
    patched = module.transform(fixture())
    assert patched.count("func _make_shadow_skeleton") == 1
    assert "var original_target_skeleton := target_skeletons[0]" in patched
    assert "var target_skeleton := _make_shadow_skeleton(original_target_skeleton)" in patched
    assert "target_skeleton.global_transform = original_target_skeleton.global_transform" in patched
    assert "original_target_skeleton.set_bone_name" not in patched
    assert patched.count("target_skeleton.set_bone_name") == 2

    try:
        module.transform(fixture().replace("semantic mapping incomplete", "semantic map changed", 1))
    except ValueError as exc:
        assert "drifted" in str(exc)
    else:
        raise AssertionError("drifted historical block was not rejected")

    try:
        module.transform(fixture() + "\nfunc _write_payload(payload: Dictionary) -> bool:\n    return false\n")
    except ValueError as exc:
        assert "anchor" in str(exc)
    else:
        raise AssertionError("ambiguous helper anchor was not rejected")

    print("CIV1_SHADOW_RETARGET_PATCH_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
