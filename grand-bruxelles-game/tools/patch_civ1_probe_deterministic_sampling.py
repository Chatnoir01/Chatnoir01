#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

NEEDLE = """    player.play(SOURCE_ANIMATION)\n    player.advance(0.0)\n    await process_frame\n    for sample_idx in range(SAMPLE_COUNT):\n"""
REPLACEMENT = """    player.play(SOURCE_ANIMATION)\n    player.advance(0.0)\n    await process_frame\n    # Freeze automatic AnimationPlayer advancement before exact seek-based sampling.\n    # RetargetModifier3D still receives a process frame after each explicit seek, but\n    # the source animation can no longer drift by a runner-dependent frame delta.\n    player.pause()\n    for sample_idx in range(SAMPLE_COUNT):\n"""


def patch_text(text: str) -> str:
    if text.count(NEEDLE) != 1:
        raise ValueError(f"expected exactly one sampling block, found {text.count(NEEDLE)}")
    patched = text.replace(NEEDLE, REPLACEMENT)
    if patched.count("player.pause()") != 1:
        raise ValueError("deterministic sampling pause was not inserted exactly once")
    return patched


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_civ1_probe_deterministic_sampling.py PROBE_GD", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    original = path.read_text(encoding="utf-8")
    patched = patch_text(original)
    path.write_text(patched, encoding="utf-8")
    print("CIV1_PROBE_DETERMINISTIC_SAMPLING_PATCH_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
