#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_node_table_uniqueness as node_table

SCHEMA = "grand-bruxelles-civ1-node-tree-topology-v2"
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


def topology_conflicts(scene_text: str) -> tuple[list[dict[str, object]], list[dict[str, object]], list[dict[str, object]]]:
    nodes = parse_nodes(scene_text)
    roots = [node for node in nodes if node["parent"] is None]
    root_conflicts: list[dict[str, object]] = []
    if len(roots) != 1:
        root_conflicts.append({
            "reason": "scene_must_have_exactly_one_root_node",
            "root_count": len(roots),
            "root_lines": [node["line"] for node in roots],
        })

    # Godot parent NodePaths are root-relative: '.' names the root. Build the
    # tree only from nodes whose parent chain is already proven reachable.
    # Keep an owner line per canonical path: a set alone would silently fold
    # duplicate declarations and make ambiguous hierarchy evidence look valid.
    reachable_paths = {"."} if len(roots) == 1 else set()
    path_owner_line: dict[str, int] = {}
    duplicate_path_conflicts: list[dict[str, object]] = []
    unresolved = [node for node in nodes if node["parent"] is not None]
    progressed = True
    while progressed and unresolved:
        progressed = False
        remaining: list[dict[str, object]] = []
        for node in unresolved:
            parent = str(node["parent"])
            if parent in reachable_paths:
                path = str(node["name"]) if parent == "." else f"{parent}/{node['name']}"
                first_line = path_owner_line.get(path)
                if first_line is not None:
                    duplicate_path_conflicts.append({
                        "line": node["line"],
                        "first_line": first_line,
                        "path": path,
                        "reason": "canonical_node_path_declared_more_than_once",
                        "raw_header": node["raw_header"],
                    })
                else:
                    path_owner_line[path] = int(node["line"])
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
    return root_conflicts, orphan_conflicts, duplicate_path_conflicts


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
    roots, orphans, duplicates = topology_conflicts(normal)
    assert roots == [] and orphans == [] and duplicates == []

    forged = '''
[gd_scene load_steps=1 format=3]
[node name="Main" type="Node3D"]
[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
'''
    # Regression precondition: legacy textual path derivation synthesizes the
    # target path even though neither parent node exists.
    assert "NpcAgent/CharacterMount/Skeleton3D" in _legacy_declared_paths(forged)
    roots, orphans, duplicates = topology_conflicts(forged)
    assert roots == [] and len(orphans) == 1 and duplicates == []

    missing_intermediate = normal.replace(
        '[node name="CharacterMount" type="Node3D" parent="NpcAgent"]\n', ""
    )
    roots, orphans, duplicates = topology_conflicts(missing_intermediate)
    assert roots == [] and len(orphans) == 1 and duplicates == []

    multiple_roots = normal + '[node name="OtherRoot" type="Node3D"]\n'
    roots, orphans, duplicates = topology_conflicts(multiple_roots)
    assert len(roots) == 1 and roots[0]["root_count"] == 2
    assert len(orphans) == 3 and duplicates == []

    duplicate_path = normal + '[node name="Skeleton3D" type="Node3D" parent="NpcAgent/CharacterMount"]\n'
    # RED precondition: the legacy set representation silently folds both
    # declarations into a single canonical path.
    legacy_paths = _legacy_declared_paths(duplicate_path)
    assert "NpcAgent/CharacterMount/Skeleton3D" in legacy_paths
    assert sum(1 for p in legacy_paths if p == "NpcAgent/CharacterMount/Skeleton3D") == 1
    roots, orphans, duplicates = topology_conflicts(duplicate_path)
    assert roots == [] and orphans == [] and len(duplicates) == 1
    assert duplicates[0]["path"] == "NpcAgent/CharacterMount/Skeleton3D"


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
    duplicate_path_conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        roots, orphans, duplicates = topology_conflicts(scene_path.read_text(encoding="utf-8"))
        root_conflicts.extend({"scene": rel, **item} for item in roots)
        orphan_conflicts.extend({"scene": rel, **item} for item in orphans)
        duplicate_path_conflicts.extend({"scene": rel, **item} for item in duplicates)

    topology_valid = not root_conflicts and not orphan_conflicts and not duplicate_path_conflicts
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_root_connected_unique_canonical_node_paths",
        "reachable_scene_count": len(scenes),
        "root_count_conflicts": root_conflicts,
        "orphan_parent_conflicts": orphan_conflicts,
        "duplicate_canonical_node_path_conflicts": duplicate_path_conflicts,
        "node_tree_topology_valid": topology_valid,
        "canonical_node_paths_unique": not duplicate_path_conflicts,
        "orphan_hierarchy_evidence_accepted": False,
        "multiple_root_evidence_accepted": False,
        "duplicate_canonical_node_path_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "repair root/orphan/duplicate canonical node-path topology before Character hierarchy evidence can be trusted" if not topology_valid else "retain root-connected unique node-tree topology gate before authored Character loaded-scene approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
