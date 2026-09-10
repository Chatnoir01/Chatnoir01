#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_node_table_uniqueness as node_table

SCHEMA = "grand-bruxelles-civ1-node-tree-topology-v1"
NODE_RE = re.compile(r'^\s*\[node\s+(.+?)\]\s*$')


def parse_nodes(scene_text: str) -> list[dict[str, object]]:
    nodes: list[dict[str, object]] = []
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = NODE_RE.match(line)
        if not match:
            continue
        pairs, residue = node_table.parse_header_attributes(match.group(1))
        if residue:
            continue
        attrs = dict(pairs)
        name = attrs.get("name")
        if not name:
            continue
        nodes.append({"line": line_number, "name": name, "parent": attrs.get("parent"), "raw_header": line.strip()})
    return nodes


def topology_conflicts(scene_text: str) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    nodes = parse_nodes(scene_text)
    roots = [node for node in nodes if node["parent"] is None]
    root_conflicts: list[dict[str, object]] = []
    if len(roots) != 1:
        root_conflicts.append({
            "reason": "scene_must_have_exactly_one_root_node",
            "root_count": len(roots),
            "root_lines": [node["line"] for node in roots],
        })

    # Godot parent NodePaths are root-relative: '.' names the root.  Build the
    # tree only from nodes whose parent chain is already proven reachable.
    reachable_paths = {"."} if len(roots) == 1 else set()
    unresolved = [node for node in nodes if node["parent"] is not None]
    progressed = True
    while progressed and unresolved:
        progressed = False
        remaining: list[dict[str, object]] = []
        for node in unresolved:
            parent = str(node["parent"])
            if parent in reachable_paths:
                path = str(node["name"]) if parent == "." else f"{parent}/{node['name']}"
                reachable_paths.add(path)
                progressed = True
            else:
                remaining.append(node)
        unresolved = remaining

    orphan_conflicts = [{
        "line": node["line"],
        "name": node["name"],
        "parent": node["parent"],
        "reason": "parent_chain_not_declared_from_scene_root",
        "raw_header": node["raw_header"],
    } for node in unresolved]
    return root_conflicts, orphan_conflicts


def _legacy_declared_paths(scene_text: str) -> set[str]:
    paths: set[str] = set()
    for node in parse_nodes(scene_text):
        attrs = {"name": str(node["name"])}
        if node["parent"] is not None:
            attrs["parent"] = str(node["parent"])
        path = node_table.declared_node_path(attrs)
        if path:
            paths.add(path)
    return paths


def self_test() -> None:
    normal = '''
[gd_scene load_steps=1 format=3]
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
'''
    roots, orphans = topology_conflicts(normal)
    assert roots == [] and orphans == []

    forged = '''
[gd_scene load_steps=1 format=3]
[node name="Main" type="Node3D"]
[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
'''
    # Regression precondition: legacy textual path derivation synthesizes the
    # exact target path even though neither parent node exists.
    assert "NpcAgent/CharacterMount/Skeleton3D" in _legacy_declared_paths(forged)
    roots, orphans = topology_conflicts(forged)
    assert roots == [] and len(orphans) == 1
    assert orphans[0]["parent"] == "NpcAgent/CharacterMount"

    missing_intermediate = normal.replace(
        '[node name="CharacterMount" type="Node3D" parent="NpcAgent"]\n', ""
    )
    roots, orphans = topology_conflicts(missing_intermediate)
    assert roots == [] and len(orphans) == 1

    multiple_roots = normal + '[node name="OtherRoot" type="Node3D"]\n'
    roots, orphans = topology_conflicts(multiple_roots)
    assert len(roots) == 1 and roots[0]["root_count"] == 2
    assert len(orphans) == 3


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_NODE_TREE_TOPOLOGY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_node_tree_topology.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    root_conflicts: list[dict[str, object]] = []
    orphan_conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        roots, orphans = topology_conflicts(scene_path.read_text(encoding="utf-8"))
        root_conflicts.extend({"scene": rel, **item} for item in roots)
        orphan_conflicts.extend({"scene": rel, **item} for item in orphans)

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_root_connected_node_parent_topology",
        "reachable_scene_count": len(scenes),
        "root_count_conflicts": root_conflicts,
        "orphan_parent_conflicts": orphan_conflicts,
        "node_tree_topology_valid": not root_conflicts and not orphan_conflicts,
        "orphan_hierarchy_evidence_accepted": False,
        "multiple_root_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "repair disconnected/orphan scene-node parent topology before Character hierarchy evidence can be trusted" if root_conflicts or orphan_conflicts else "retain root-connected node-tree topology gate before authored Character loaded-scene approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
