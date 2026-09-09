#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-integration-readiness-v1"


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: civ1_integration_readiness.py MAIN_TSCN NPC_AGENT OUT", file=sys.stderr)
        return 2
    main_tscn = Path(sys.argv[1])
    npc_agent = Path(sys.argv[2])
    out = Path(sys.argv[3])
    scene = main_tscn.read_text(encoding="utf-8")
    agent = npc_agent.read_text(encoding="utf-8")

    character_mount_tokens = len(re.findall(r"CharacterMount", scene + "\n" + agent))
    skeleton_tokens = len(re.findall(r"Skeleton3D", scene + "\n" + agent))
    player_reuse_hits = [
        line.strip()
        for line in agent.splitlines()
        if re.search(r"(?:preload|load)\([^\n]*player", line, re.I)
    ]
    procedural_cube_hits = [
        line.strip()
        for line in agent.splitlines()
        if re.search(r"\b(?:BoxMesh|CSGBox3D)\b", line)
    ]

    hierarchy_statically_addressable = character_mount_tokens > 0 and skeleton_tokens > 0
    result = {
        "schema": SCHEMA,
        "canonical_scene": str(main_tscn),
        "npc_agent": str(npc_agent),
        "character_mount_token_count": character_mount_tokens,
        "skeleton3d_token_count": skeleton_tokens,
        "hierarchy_statically_addressable": hierarchy_statically_addressable,
        "player_character_reuse_detected": bool(player_reuse_hits),
        "player_character_reuse_hits": player_reuse_hits,
        "procedural_cube_fallback_detected": bool(procedural_cube_hits),
        "procedural_cube_fallback_hits": procedural_cube_hits,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "rerun loaded-scene CIV-1 probe and capture samples 71/72/73"
            if hierarchy_statically_addressable
            else "runtime owner must integrate authored CharacterMount + Skeleton3D before placement capture"
        ),
    }

    if result["player_character_reuse_detected"]:
        print("CIV1_INTEGRATION_READINESS_FAIL: player character reuse detected", file=sys.stderr)
        return 1
    if result["procedural_cube_fallback_detected"]:
        print("CIV1_INTEGRATION_READINESS_FAIL: procedural cube fallback detected", file=sys.stderr)
        return 1

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
