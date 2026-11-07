#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_node_table_uniqueness as node_table

SCHEMA = "grand-bruxelles-civ1-node-property-uniqueness-v1"
NODE_RE = re.compile(r'^\s*\[node\s+(.+?)\]\s*$')


def property_conflicts(scene_text: str) -> list[dict[str, object]]:
    conflicts: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        node_match = NODE_RE.match(line)
        if node_match:
            pairs, residue = node_table.parse_header_attributes(node_match.group(1))
            attrs = dict(pairs) if not residue else {}
            current = {
                "line": line_number,
                "path": node_table.declared_node_path(attrs) or "<unresolved-node>",
                "properties": [],
            }
            continue
        if line.lstrip().startswith("["):
            if current is not None:
                conflicts.extend(_duplicates_for_node(current))
            current = None
            continue
        if current is None or "=" not in line:
            continue
        key, _ = line.split("=", 1)
        key = key.strip()
        if key:
            properties = current["properties"]
            assert isinstance(properties, list)
            properties.append((key, line_number))
    if current is not None:
        conflicts.extend(_duplicates_for_node(current))
    return conflicts


def _duplicates_for_node(node: dict[str, object]) -> list[dict[str, object]]:
    properties = node["properties"]
    assert isinstance(properties, list)
    counts = Counter(key for key, _ in properties)
    out: list[dict[str, object]] = []
    for key in sorted(name for name, count in counts.items() if count > 1):
        out.append({
            "node_path": node["path"],
            "node_header_line": node["line"],
            "property": key,
            "assignment_count": counts[key],
            "assignment_lines": [line for name, line in properties if name == key],
            "reason": "duplicate_property_assignment_in_single_node_block",
        })
    return out


def _legacy_property_dict(scene_text: str) -> dict[str, str]:
    blocks = skin.parse_node_blocks(scene_text)
    for block in blocks:
        attrs = block.get("attrs")
        if isinstance(attrs, dict) and attrs.get("name") == "Body":
            props = block.get("props")
            assert isinstance(props, dict)
            return {str(k): str(v) for k, v in props.items()}
    return {}


def self_test() -> None:
    normal = '''
[gd_scene load_steps=1 format=3]
[node name="Main" type="Node3D"]
[node name="Body" type="MeshInstance3D" parent="."]
mesh = SubResource("Mesh_body")
skin = SubResource("Skin_body")
material_override = SubResource("Mat_body")
'''
    assert property_conflicts(normal) == []

    forged = normal.replace(
        'mesh = SubResource("Mesh_body")',
        'mesh = SubResource("MissingMesh")\nmesh = SubResource("Mesh_body")',
    )
    legacy = _legacy_property_dict(forged)
    assert legacy.get("mesh") == 'SubResource("Mesh_body")', "regression precondition: legacy dict silently keeps only the last duplicate property assignment"
    conflicts = property_conflicts(forged)
    assert len(conflicts) == 1
    assert conflicts[0]["property"] == "mesh"
    assert conflicts[0]["assignment_count"] == 2

    separate_nodes = normal + '''
[node name="Body2" type="MeshInstance3D" parent="."]
mesh = SubResource("Mesh_body")
'''
    assert property_conflicts(separate_nodes) == [], "the same property on different nodes must remain valid"

    cross_section = normal + '''
[sub_resource type="Resource" id="Carrier"]
mesh = SubResource("OtherMesh")
'''
    assert property_conflicts(cross_section) == [], "non-node section properties must not bleed into the preceding node"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_NODE_PROPERTY_UNIQUENESS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_node_property_uniqueness.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        conflicts.extend({"scene": rel, **item} for item in property_conflicts(scene_path.read_text(encoding="utf-8")))

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_unique_property_assignment_per_node_block",
        "reachable_scene_count": len(scenes),
        "duplicate_node_property_conflicts": conflicts,
        "node_property_assignments_unique": not conflicts,
        "duplicate_node_property_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "remove duplicate node property assignments before authored Character integrity evidence can be trusted" if conflicts else "retain node-property uniqueness gate before authored Character loaded-scene approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
