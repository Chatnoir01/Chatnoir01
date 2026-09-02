#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path

SUCCESS_MARKER = "CIV1_GLOBAL_CHAIN_DIAGNOSTIC_OK"
PATTERNS = [
    re.compile(r"skin.*bind.*bone.*(?:not found|missing|invalid)", re.I),
    re.compile(r"skin.*bind.*skeleton(?:3d)?.*has no bone(?: by that name)?", re.I),
    re.compile(r"bone.*(?:not found|missing).*skeleton", re.I),
    re.compile(r"bind.*(?:not found|missing).*skeleton", re.I),
]
BONE = re.compile(r"(?:mixamorig[_:])?[A-Za-z0-9_]*(?:Hips|Foot|Leg|Spine|Arm|Hand|Head)[A-Za-z0-9_]*")


def assess(text: str):
    lines = []
    bones = set()
    for line in text.splitlines():
        if any(p.search(line) for p in PATTERNS):
            lines.append(line.strip())
            bones.update(BONE.findall(line))
    diagnostic_complete = SUCCESS_MARKER in text
    binds_clean = not lines
    verified = diagnostic_complete and binds_clean
    if lines:
        verdict = "BLOCK_SKIN_BIND_INTEGRITY"
    elif not diagnostic_complete:
        verdict = "BLOCK_INCOMPLETE_DIAGNOSTIC"
    else:
        verdict = "ALLOW_DIAGNOSTIC_ONLY"
    return {
        "format": "grand-bruxelles-civ1-skin-bind-integrity-v4",
        "diagnostic_complete": diagnostic_complete,
        "skin_bind_integrity_verified": verified,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "error_count": len(lines),
        "affected_bones": sorted(bones),
        "verdict": verdict,
        "errors": lines[:100],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--output")
    a = ap.parse_args()
    result = assess(Path(a.log).read_text(errors="replace"))
    out = json.dumps(result, indent=2, sort_keys=True)
    if a.output:
        Path(a.output).write_text(out + "\n")
    print(out)
    raise SystemExit(0 if result["skin_bind_integrity_verified"] else 2)


if __name__ == "__main__":
    main()
