#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-integration-readiness-v2"
NODE_HEADER_RE = re.compile(r"^\s*\[node\s+(.+?)\]\s*$")
ATTR_RE = re.compile(r'\b(name|type|parent)="([^"]*)"')


def parse_nodes(scene: str) -> list[dict[str, str]]:
    nodes: list[dict[str, str]] = []
    for line in scene.splitlines():
        match = NODE_HEADER_RE.match(line)
        if not match:
            continue
        attrs = dict(ATTR_RE.findall(match.group(1)))
        if "name" not in attrs:
            continue
        nodes.append(attrs)
    return nodes


def node_path(node: dict[str, str]) -> str:
    parent = node.get("parent", ".")
    name = node["name"]
    if parent in ("", "."):
        return name
    return f"{parent}/{name}".strip("/")


def structural_hierarchies(scene: str) -> list[dict[str, str]]:
    nodes = parse_nodes(scene)
    by_path = {node_path(node): node for node in nodes}
    hierarchies: list[dict[str, str]] = []
    for mount_path, mount in by_path.items():
        if mount.get("name") != "CharacterMount" or mount.get("type") != "Node3D":
            continue
        parent_path = mount.get("parent", "")
        agent = by_path.get(parent_path)
        if not agent or agent.get("name") != "NpcAgent" or agent.get("type") != "CharacterBody3D":
            continue
        prefix = mount_path + "/"
        for skeleton_path, skeleton in by_path.items():
            if skeleton.get("type") != "Skeleton3D" or not skeleton_path.startswith(prefix):
                continue
            hierarchies.append({
                "npc_agent_path": parent_path,
                "character_mount_path": mount_path,
                "skeleton_path": skeleton_path,
            })
    return hierarchies


def detect_agent_hazards(agent: str) -> tuple[list[str], list[str]]:
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
    return player_reuse_hits, procedural_cube_hits


def regression_self_test() -> None:
    forged = '''
[node name="Main" type="Node3D"]
# CharacterMount Skeleton3D NpcAgent
[node name="Decoy" type="Node3D" parent="."]
metadata/note = "NpcAgent CharacterMount Skeleton3D"
'''
    assert structural_hierarchies(forged) == [], "token-only evidence must not become structural readiness"

    disconnected = '''
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="Other"]
[node name="Skeleton" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
'''
    assert structural_hierarchies(disconnected) == [], "disconnected mount must fail closed"

    wrong_types = '''
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="Node3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Skeleton" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
'''
    assert structural_hierarchies(wrong_types) == [], "wrong NpcAgent type must fail closed"

    valid = '''
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Skeleton" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
'''
    found = structural_hierarchies(valid)
    assert len(found) == 1, "canonical structural hierarchy should be recognized"
    assert found[0]["character_mount_path"] == "NpcAgent/CharacterMount"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        regression_self_test()
        print("CIV1_INTEGRATION_READINESS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 4:
        print("usage: civ1_integration_readiness.py MAIN_TSCN NPC_AGENT OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1])
    npc_agent = Path(sys.argv[2])
    out = Path(sys.argv[3])
    scene = main_tscn.read_text(encoding="utf-8")
    agent = npc_agent.read_text(encoding="utf-8")

    hierarchies = structural_hierarchies(scene)
    player_reuse_hits, procedural_cube_hits = detect_agent_hazards(agent)
    result = {
        "schema": SCHEMA,
        "canonical_scene": str(main_tscn),
        "npc_agent": str(npc_agent),
        "structural_hierarchy_count": len(hierarchies),
        "structural_hierarchies": hierarchies,
        "hierarchy_statically_addressable": bool(hierarchies),
        "evidence_mode": "parsed_tscn_node_headers",
        "token_only_evidence_accepted": False,
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
            if hierarchies
            else "runtime owner must integrate authored NpcAgent > CharacterMount > Skeleton3D before placement capture"
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
