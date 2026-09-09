#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-resource-table-uniqueness-v2"
EXT_RE = re.compile(r'^\s*\[ext_resource\s+(.+?)\]\s*$')
SUB_RE = re.compile(r'^\s*\[sub_resource\s+(.+?)\]\s*$')
ATTR_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"')


def resource_table_conflicts(scene_text: str) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    seen: dict[tuple[str, str], list[dict[str, str]]] = {}
    attribute_conflicts: list[dict[str, object]] = []

    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = EXT_RE.match(line)
        kind = "ExtResource"
        if not match:
            match = SUB_RE.match(line)
            kind = "SubResource"
        if not match:
            continue

        attr_pairs = ATTR_RE.findall(match.group(1))
        attr_counts = Counter(name for name, _ in attr_pairs)
        duplicate_attributes = sorted(name for name, count in attr_counts.items() if count > 1)
        if duplicate_attributes:
            attribute_conflicts.append({
                "kind": kind,
                "line": line_number,
                "duplicate_attributes": duplicate_attributes,
                "attribute_occurrences": {
                    name: attr_counts[name] for name in duplicate_attributes
                },
                "raw_header": line.strip(),
            })

        attrs = dict(attr_pairs)
        rid = attrs.get("id")
        if not rid:
            continue
        seen.setdefault((kind, rid), []).append({
            "line": str(line_number),
            "type": attrs.get("type", ""),
            "path": attrs.get("path", ""),
        })

    id_conflicts: list[dict[str, object]] = []
    for (kind, rid), declarations in sorted(seen.items()):
        if len(declarations) <= 1:
            continue
        id_conflicts.append({
            "kind": kind,
            "id": rid,
            "declaration_count": len(declarations),
            "declarations": declarations,
        })
    return id_conflicts, attribute_conflicts


def duplicate_resource_ids(scene_text: str) -> list[dict[str, object]]:
    return resource_table_conflicts(scene_text)[0]


def self_test() -> None:
    normal = '''
[gd_scene load_steps=3 format=3]
[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]
[sub_resource type="Skin" id="Skin_body"]
[node name="Main" type="Node3D"]
'''
    ids, attrs = resource_table_conflicts(normal)
    assert ids == []
    assert attrs == []

    duplicate_ext = normal.replace(
        '[sub_resource type="Skin" id="Skin_body"]',
        '[ext_resource type="Skin" path="res://assets/body.skin" id="Mesh_body"]\n[sub_resource type="Skin" id="Skin_body"]',
    )
    ids, attrs = resource_table_conflicts(duplicate_ext)
    assert len(ids) == 1
    assert attrs == []
    assert ids[0]["kind"] == "ExtResource"
    assert ids[0]["id"] == "Mesh_body"
    assert ids[0]["declaration_count"] == 2

    parsed = skin.parse_resource_table(duplicate_ext)
    assert parsed[("ExtResource", "Mesh_body")]["type"] == "Skin", (
        "regression precondition: legacy dict parsing silently overwrites the first duplicate resource id"
    )

    duplicate_sub = normal + '\n[sub_resource type="ArrayMesh" id="Skin_body"]\n'
    ids, attrs = resource_table_conflicts(duplicate_sub)
    assert len(ids) == 1
    assert attrs == []
    assert ids[0]["kind"] == "SubResource"
    assert ids[0]["id"] == "Skin_body"

    cross_kind_same_id = normal + '\n[sub_resource type="ArrayMesh" id="Mesh_body"]\n'
    ids, attrs = resource_table_conflicts(cross_kind_same_id)
    assert ids == []
    assert attrs == []

    duplicate_id_attribute = normal.replace(
        '[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]',
        '[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_old" id="Mesh_body"]',
    )
    ids, attrs = resource_table_conflicts(duplicate_id_attribute)
    assert ids == [], "a repeated id attribute inside one header is not a duplicate declaration"
    assert len(attrs) == 1
    assert attrs[0]["duplicate_attributes"] == ["id"]
    assert attrs[0]["attribute_occurrences"]["id"] == 2
    parsed = skin.parse_resource_table(duplicate_id_attribute)
    assert ("ExtResource", "Mesh_body") in parsed, (
        "regression precondition: legacy dict parsing silently keeps the final repeated id attribute"
    )
    assert ("ExtResource", "Mesh_old") not in parsed

    duplicate_type_attribute = normal.replace(
        '[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]',
        '[ext_resource type="Skin" type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]',
    )
    ids, attrs = resource_table_conflicts(duplicate_type_attribute)
    assert ids == []
    assert len(attrs) == 1
    assert attrs[0]["duplicate_attributes"] == ["type"]
    parsed = skin.parse_resource_table(duplicate_type_attribute)
    assert parsed[("ExtResource", "Mesh_body")]["type"] == "ArrayMesh", (
        "regression precondition: legacy dict parsing silently keeps the final repeated type attribute"
    )

    duplicate_path_attribute = normal.replace(
        'path="res://assets/body.mesh"',
        'path="res://assets/forged.mesh" path="res://assets/body.mesh"',
    )
    ids, attrs = resource_table_conflicts(duplicate_path_attribute)
    assert ids == []
    assert len(attrs) == 1
    assert attrs[0]["duplicate_attributes"] == ["path"]


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_RESOURCE_TABLE_UNIQUENESS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_resource_table_uniqueness.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    id_conflicts: list[dict[str, object]] = []
    attribute_conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        text = scene_path.read_text(encoding="utf-8")
        scene_ids, scene_attrs = resource_table_conflicts(text)
        for conflict in scene_ids:
            id_conflicts.append({"scene": rel, **conflict})
        for conflict in scene_attrs:
            attribute_conflicts.append({"scene": rel, **conflict})

    identity_unambiguous = not id_conflicts and not attribute_conflicts
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_unique_resource_id_namespace_plus_unambiguous_resource_header_attributes",
        "reachable_scene_count": len(scenes),
        "duplicate_resource_id_conflicts": id_conflicts,
        "duplicate_resource_attribute_conflicts": attribute_conflicts,
        "resource_header_attributes_unambiguous": not attribute_conflicts,
        "resource_table_identity_unambiguous": identity_unambiguous,
        "duplicate_resource_id_evidence_accepted": False,
        "duplicate_resource_attribute_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "remove duplicate ExtResource/SubResource ids and repeated header attributes before authored Character integrity can be trusted"
            if not identity_unambiguous
            else "retain unique resource-id and unambiguous-header gates before authored Character loaded-scene approval"
        ),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
