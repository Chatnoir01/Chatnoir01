#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_node_table_uniqueness as node_table

SCHEMA = "grand-bruxelles-civ1-parent-nodepath-canonicality-v1"
NODE_RE = re.compile(r'^\s*\[node\s+(.+?)\]\s*$')


def parent_path_reason(parent: str) -> str | None:
    if parent == ".":
        return None
    if not parent:
        return "parent_nodepath_must_not_be_empty"
    if parent.startswith("/"):
        return "parent_nodepath_must_be_relative"
    if parent.endswith("/"):
        return "parent_nodepath_must_not_have_trailing_separator"
    segments = parent.split("/")
    if any(segment == "" for segment in segments):
        return "parent_nodepath_must_not_have_empty_segments"
    if any(segment == "." for segment in segments):
        return "parent_nodepath_must_not_have_current_segments"
    if any(segment == ".." for segment in segments):
        return "parent_nodepath_must_not_have_parent_traversal_segments"
    return None


def parent_nodepath_conflicts(scene_text: str) -> list[dict[str, object]]:
    conflicts: list[dict[str, object]] = []
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = NODE_RE.match(line)
        if not match:
            continue
        pairs, residue = node_table.parse_header_attributes(match.group(1))
        if residue:
            # Node-table owns malformed syntax; do not reinterpret partial headers here.
            continue
        attrs = dict(pairs)
        parent = attrs.get("parent")
        if parent is None:
            continue
        reason = parent_path_reason(parent)
        if reason:
            conflicts.append({
                "line": line_number,
                "parent": parent,
                "reason": reason,
                "raw_header": line.strip(),
            })
    return conflicts


def _legacy_path(attrs: dict[str, str]) -> str | None:
    """Reproduce the pre-gate textual path derivation without NodePath canonicality."""
    return node_table.declared_node_path(attrs)


def self_test() -> None:
    normal = '''
[gd_scene load_steps=1 format=3]
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
'''
    assert parent_nodepath_conflicts(normal) == []

    traversal = normal.replace(
        'parent="NpcAgent/CharacterMount"]',
        'parent="NpcAgent/CharacterMount/../CharacterMount"]',
    )
    conflicts = parent_nodepath_conflicts(traversal)
    assert len(conflicts) == 1
    assert conflicts[0]["reason"] == "parent_nodepath_must_not_have_parent_traversal_segments"
    assert _legacy_path({"name": "Skeleton3D", "parent": "NpcAgent/CharacterMount/../CharacterMount"}) == "NpcAgent/CharacterMount/../CharacterMount/Skeleton3D"

    current_segment = normal.replace('parent="NpcAgent"]', 'parent="NpcAgent/./"]')
    reasons = {c["reason"] for c in parent_nodepath_conflicts(current_segment)}
    assert "parent_nodepath_must_not_have_trailing_separator" in reasons or "parent_nodepath_must_not_have_current_segments" in reasons

    doubled = normal.replace('parent="NpcAgent/CharacterMount"]', 'parent="NpcAgent//CharacterMount"]')
    conflicts = parent_nodepath_conflicts(doubled)
    assert len(conflicts) == 1 and conflicts[0]["reason"] == "parent_nodepath_must_not_have_empty_segments"

    absolute = normal.replace('parent="NpcAgent/CharacterMount"]', 'parent="/NpcAgent/CharacterMount"]')
    conflicts = parent_nodepath_conflicts(absolute)
    assert len(conflicts) == 1 and conflicts[0]["reason"] == "parent_nodepath_must_be_relative"

    trailing = normal.replace('parent="NpcAgent/CharacterMount"]', 'parent="NpcAgent/CharacterMount/"]')
    conflicts = parent_nodepath_conflicts(trailing)
    assert len(conflicts) == 1 and conflicts[0]["reason"] == "parent_nodepath_must_not_have_trailing_separator"

    escaped_traversal = normal.replace('parent="NpcAgent/CharacterMount"]', 'parent="NpcAgent/CharacterMount/\\u002e\\u002e/CharacterMount"]')
    conflicts = parent_nodepath_conflicts(escaped_traversal)
    assert len(conflicts) == 1 and conflicts[0]["parent"] == "NpcAgent/CharacterMount/../CharacterMount"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_PARENT_NODEPATH_CANONICALITY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_parent_nodepath_canonicality.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for item in parent_nodepath_conflicts(scene_path.read_text(encoding="utf-8")):
            conflicts.append({"scene": rel, **item})

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_canonical_relative_parent_nodepaths",
        "reachable_scene_count": len(scenes),
        "parent_nodepath_conflicts": conflicts,
        "parent_nodepaths_canonical": not conflicts,
        "parent_traversal_alias_evidence_accepted": False,
        "empty_parent_segment_alias_evidence_accepted": False,
        "absolute_parent_nodepath_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "repair parent NodePath alias/canonicality conflicts before Character hierarchy evidence can be trusted" if conflicts else "retain canonical parent NodePath gate before authored Character loaded-scene approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
