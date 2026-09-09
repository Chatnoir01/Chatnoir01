#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
import tempfile
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-resource-table-uniqueness-v1"
EXT_RE = re.compile(r'^\s*\[ext_resource\s+(.+?)\]\s*$')
SUB_RE = re.compile(r'^\s*\[sub_resource\s+(.+?)\]\s*$')
ATTR_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"')


def duplicate_resource_ids(scene_text: str) -> list[dict[str, object]]:
    seen: dict[tuple[str, str], list[dict[str, str]]] = {}
    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        match = EXT_RE.match(line)
        kind = "ExtResource"
        if not match:
            match = SUB_RE.match(line)
            kind = "SubResource"
        if not match:
            continue
        attrs = dict(ATTR_RE.findall(match.group(1)))
        rid = attrs.get("id")
        if not rid:
            continue
        seen.setdefault((kind, rid), []).append({
            "line": str(line_number),
            "type": attrs.get("type", ""),
            "path": attrs.get("path", ""),
        })

    conflicts: list[dict[str, object]] = []
    for (kind, rid), declarations in sorted(seen.items()):
        if len(declarations) <= 1:
            continue
        conflicts.append({
            "kind": kind,
            "id": rid,
            "declaration_count": len(declarations),
            "declarations": declarations,
        })
    return conflicts


def self_test() -> None:
    normal = '''
[gd_scene load_steps=3 format=3]
[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]
[sub_resource type="Skin" id="Skin_body"]
[node name="Main" type="Node3D"]
'''
    assert duplicate_resource_ids(normal) == []

    duplicate_ext = normal.replace(
        '[sub_resource type="Skin" id="Skin_body"]',
        '[ext_resource type="Skin" path="res://assets/body.skin" id="Mesh_body"]\n[sub_resource type="Skin" id="Skin_body"]',
    )
    conflicts = duplicate_resource_ids(duplicate_ext)
    assert len(conflicts) == 1
    assert conflicts[0]["kind"] == "ExtResource"
    assert conflicts[0]["id"] == "Mesh_body"
    assert conflicts[0]["declaration_count"] == 2

    parsed = skin.parse_resource_table(duplicate_ext)
    assert parsed[("ExtResource", "Mesh_body")]["type"] == "Skin", (
        "regression precondition: legacy dict parsing silently overwrites the first duplicate resource id"
    )

    duplicate_sub = normal + '\n[sub_resource type="ArrayMesh" id="Skin_body"]\n'
    conflicts = duplicate_resource_ids(duplicate_sub)
    assert len(conflicts) == 1
    assert conflicts[0]["kind"] == "SubResource"
    assert conflicts[0]["id"] == "Skin_body"

    cross_kind_same_id = normal + '\n[sub_resource type="ArrayMesh" id="Mesh_body"]\n'
    assert duplicate_resource_ids(cross_kind_same_id) == [], (
        "ExtResource and SubResource namespaces are distinct and must not be conflated"
    )


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
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        text = scene_path.read_text(encoding="utf-8")
        for conflict in duplicate_resource_ids(text):
            conflicts.append({"scene": rel, **conflict})

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_unique_resource_id_namespace",
        "reachable_scene_count": len(scenes),
        "duplicate_resource_id_conflicts": conflicts,
        "resource_table_identity_unambiguous": not conflicts,
        "duplicate_resource_id_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "remove duplicate ExtResource/SubResource ids before authored Character integrity can be trusted"
            if conflicts
            else "retain unique resource-id gate before authored Character loaded-scene approval"
        ),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
