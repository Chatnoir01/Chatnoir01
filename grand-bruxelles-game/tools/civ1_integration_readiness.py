#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
import tempfile
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-integration-readiness-v3"
NODE_HEADER_RE = re.compile(r"^\s*\[node\s+(.+?)\]\s*$")
EXT_RESOURCE_HEADER_RE = re.compile(r"^\s*\[ext_resource\s+(.+?)\]\s*$")
QUOTED_ATTR_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"')
INSTANCE_RE = re.compile(r'\binstance=ExtResource\("([^"]+)"\)')


def parse_nodes(scene: str) -> list[dict[str, str]]:
    nodes: list[dict[str, str]] = []
    for line in scene.splitlines():
        match = NODE_HEADER_RE.match(line)
        if not match:
            continue
        attrs = dict(QUOTED_ATTR_RE.findall(match.group(1)))
        instance_match = INSTANCE_RE.search(match.group(1))
        if instance_match:
            attrs["instance"] = instance_match.group(1)
        if "name" not in attrs:
            continue
        nodes.append(attrs)
    return nodes


def parse_packed_scene_resources(scene: str) -> dict[str, str]:
    resources: dict[str, str] = {}
    for line in scene.splitlines():
        match = EXT_RESOURCE_HEADER_RE.match(line)
        if not match:
            continue
        attrs = dict(QUOTED_ATTR_RE.findall(match.group(1)))
        if attrs.get("type") != "PackedScene":
            continue
        resource_id = attrs.get("id")
        path = attrs.get("path")
        if resource_id and path:
            resources[resource_id] = path
    return resources


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


def res_path_to_file(project_root: Path, resource_path: str) -> Path | None:
    if not resource_path.startswith("res://"):
        return None
    relative = resource_path[len("res://"):]
    candidate = (project_root / relative).resolve()
    root = project_root.resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        return None
    return candidate


def reachable_scene_files(main_tscn: Path, project_root: Path) -> list[Path]:
    root = project_root.resolve()
    pending = [main_tscn.resolve()]
    visited: set[Path] = set()
    reachable: list[Path] = []
    while pending:
        scene_path = pending.pop()
        if scene_path in visited:
            continue
        visited.add(scene_path)
        try:
            scene_path.relative_to(root)
        except ValueError:
            continue
        if not scene_path.is_file():
            continue
        scene = scene_path.read_text(encoding="utf-8")
        reachable.append(scene_path)
        packed = parse_packed_scene_resources(scene)
        instantiated_ids = {
            node["instance"] for node in parse_nodes(scene) if node.get("instance")
        }
        for resource_id in sorted(instantiated_ids):
            resource_path = packed.get(resource_id)
            if not resource_path:
                continue
            child = res_path_to_file(project_root, resource_path)
            if child is not None and child.suffix == ".tscn":
                pending.append(child)
    return reachable


def reachable_structural_hierarchies(main_tscn: Path, project_root: Path) -> tuple[list[dict[str, str]], list[str]]:
    hierarchies: list[dict[str, str]] = []
    scenes: list[str] = []
    for scene_path in reachable_scene_files(main_tscn, project_root):
        scene = scene_path.read_text(encoding="utf-8")
        relative = scene_path.resolve().relative_to(project_root.resolve()).as_posix()
        scenes.append(relative)
        for hierarchy in structural_hierarchies(scene):
            enriched = dict(hierarchy)
            enriched["scene"] = relative
            hierarchies.append(enriched)
    return hierarchies, scenes


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

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        game = root / "game"
        game.mkdir()
        main_path = game / "main.tscn"
        reachable_path = game / "civ1.tscn"
        unused_path = game / "unused.tscn"
        main_path.write_text('''
[gd_scene load_steps=2 format=3]
[ext_resource type="PackedScene" path="res://game/civ1.tscn" id="1_civ1"]
[node name="Main" type="Node3D"]
[node name="Civilian" parent="." instance=ExtResource("1_civ1")]
''', encoding="utf-8")
        reachable_path.write_text(valid, encoding="utf-8")
        unused_path.write_text(valid, encoding="utf-8")
        reachable, scene_list = reachable_structural_hierarchies(main_path, root)
        assert len(reachable) == 1, "instanced PackedScene hierarchy must be reachable"
        assert reachable[0]["scene"] == "game/civ1.tscn"
        assert "game/unused.tscn" not in scene_list, "unused authored scene must not claim canonical readiness"

        main_path.write_text('''
[gd_scene load_steps=2 format=3]
[ext_resource type="PackedScene" path="res://game/civ1.tscn" id="1_civ1"]
[node name="Main" type="Node3D"]
''', encoding="utf-8")
        unreachable, scene_list = reachable_structural_hierarchies(main_path, root)
        assert unreachable == [], "declared-but-not-instanced PackedScene must fail closed"
        assert scene_list == ["game/main.tscn"]


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        regression_self_test()
        print("CIV1_INTEGRATION_READINESS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 4:
        print("usage: civ1_integration_readiness.py MAIN_TSCN NPC_AGENT OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    npc_agent = Path(sys.argv[2]).resolve()
    out = Path(sys.argv[3])
    project_root = main_tscn.parent.parent
    agent = npc_agent.read_text(encoding="utf-8")

    hierarchies, reachable_scenes = reachable_structural_hierarchies(main_tscn, project_root)
    player_reuse_hits, procedural_cube_hits = detect_agent_hazards(agent)
    result = {
        "schema": SCHEMA,
        "canonical_scene": str(main_tscn),
        "npc_agent": str(npc_agent),
        "structural_hierarchy_count": len(hierarchies),
        "structural_hierarchies": hierarchies,
        "hierarchy_statically_addressable": bool(hierarchies),
        "evidence_mode": "reachable_packed_scene_graph",
        "reachable_scene_count": len(reachable_scenes),
        "reachable_scenes": reachable_scenes,
        "declared_but_uninstanced_scene_evidence_accepted": False,
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
            else "runtime owner must integrate authored NpcAgent > CharacterMount > Skeleton3D into the canonical reachable scene graph before placement capture"
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
