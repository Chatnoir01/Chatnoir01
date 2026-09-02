#!/usr/bin/env python3
"""Fail closed on Godot Skeleton3D/Skin bind integrity errors in CIV-1 probes."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

PATTERN = re.compile(
    r"Skin bind #(?P<bind>\d+) contains named bind '(?P<bone>[^']+)' but Skeleton3D has no bone by that name\."
)


def assess(log_text: str) -> dict:
    matches = [
        {"bind_index": int(match.group("bind")), "bone_name": match.group("bone")}
        for match in PATTERN.finditer(log_text)
    ]
    unique_bones = sorted({item["bone_name"] for item in matches})
    return {
        "format": "grand-bruxelles-civ1-skin-bind-integrity-v1",
        "skin_bind_error_count": len(matches),
        "missing_bone_names": unique_bones,
        "skin_bind_integrity_verified": len(matches) == 0,
        "diagnostic_only": True,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("probe_log", type=Path)
    parser.add_argument("output_json", type=Path)
    args = parser.parse_args()

    result = assess(args.probe_log.read_text(encoding="utf-8", errors="replace"))
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    if not result["skin_bind_integrity_verified"]:
        print("CIV1_SKIN_BIND_INTEGRITY_BLOCKED")
        return 4
    print("CIV1_SKIN_BIND_INTEGRITY_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
