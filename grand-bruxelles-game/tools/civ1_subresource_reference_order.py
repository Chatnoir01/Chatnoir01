#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_resource_table_uniqueness as table

SCHEMA = "grand-bruxelles-civ1-subresource-reference-order-v1"
SUBRESOURCE_REF_RE = re.compile(r'SubResource\("((?:\\.|[^"\\])*)"\)')


def _decode_ref_id(raw: str) -> str | None:
    try:
        value = json.loads('"' + raw + '"')
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    return value if isinstance(value, str) else None


def subresource_reference_order_conflicts(scene_text: str) -> list[dict[str, object]]:
    declarations: dict[str, int] = {}
    current_id: str | None = None
    current_line = 0
    conflicts: list[dict[str, object]] = []

    for line_number, line in enumerate(scene_text.splitlines(), start=1):
        sub_match = table.SUB_RE.match(line)
        if sub_match:
            pairs, residue = table.parse_header_attributes(sub_match.group(1))
            attrs = dict(pairs)
            current_id = attrs.get("id") if not residue else None
            current_line = line_number
            if current_id:
                declarations.setdefault(current_id, line_number)
            continue

        if line.lstrip().startswith("["):
            current_id = None
            current_line = 0
            continue

        if current_id is None or "=" not in line:
            continue

        _, raw_value = line.split("=", 1)
        for match in SUBRESOURCE_REF_RE.finditer(raw_value):
            ref_id = _decode_ref_id(match.group(1))
            if ref_id is None:
                conflicts.append({
                    "line": line_number,
                    "owner_subresource_id": current_id,
                    "owner_header_line": current_line,
                    "referenced_subresource_id": None,
                    "reason": "invalid_subresource_reference_escape",
                })
                continue
            declaration_line = declarations.get(ref_id)
            if declaration_line is None:
                conflicts.append({
                    "line": line_number,
                    "owner_subresource_id": current_id,
                    "owner_header_line": current_line,
                    "referenced_subresource_id": ref_id,
                    "reason": "missing_or_forward_subresource_reference",
                })
            elif declaration_line >= current_line:
                conflicts.append({
                    "line": line_number,
                    "owner_subresource_id": current_id,
                    "owner_header_line": current_line,
                    "referenced_subresource_id": ref_id,
                    "referenced_header_line": declaration_line,
                    "reason": "subresource_reference_not_declared_before_owner",
                })
    return conflicts


def self_test() -> None:
    canonical = '''
[gd_scene format=3]
[sub_resource type="StandardMaterial3D" id="Mat_body"]
[sub_resource type="ArrayMesh" id="Mesh_body"]
surface_0/material = SubResource("Mat_body")
[node name="Main" type="Node3D"]
'''
    assert subresource_reference_order_conflicts(canonical) == []

    forward = '''
[gd_scene format=3]
[sub_resource type="ArrayMesh" id="Mesh_body"]
surface_0/material = SubResource("Mat_body")
[sub_resource type="StandardMaterial3D" id="Mat_body"]
[node name="Main" type="Node3D"]
'''
    legacy = skin.parse_resource_table(forward)
    assert ("SubResource", "Mat_body") in legacy
    conflicts = subresource_reference_order_conflicts(forward)
    assert len(conflicts) == 1
    assert conflicts[0]["reason"] == "missing_or_forward_subresource_reference"

    missing = canonical.replace('SubResource("Mat_body")', 'SubResource("MissingMat")')
    conflicts = subresource_reference_order_conflicts(missing)
    assert len(conflicts) == 1 and conflicts[0]["referenced_subresource_id"] == "MissingMat"

    nested = '''
[gd_scene format=3]
[sub_resource type="Resource" id="Leaf"]
[sub_resource type="Resource" id="Carrier"]
payload = [SubResource("Leaf"), {"again": SubResource("Leaf")}]
[node name="Main" type="Node3D"]
'''
    assert subresource_reference_order_conflicts(nested) == []

    node_reference = canonical + '\n[node name="Body" type="MeshInstance3D" parent="."]\nmesh = SubResource("Mesh_body")\n'
    assert subresource_reference_order_conflicts(node_reference) == []


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_SUBRESOURCE_REFERENCE_ORDER_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_subresource_reference_order.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []

    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for conflict in subresource_reference_order_conflicts(scene_path.read_text(encoding="utf-8")):
            conflicts.append({"scene": rel, **conflict})

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_internal_subresource_reference_declaration_order",
        "reachable_scene_count": len(scenes),
        "subresource_reference_order_conflicts": conflicts,
        "subresource_reference_order_valid": not conflicts,
        "forward_subresource_reference_evidence_accepted": False,
        "missing_subresource_reference_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "retain backward-only internal SubResource reference order before authored Character loaded-scene approval"
            if not conflicts
            else "declare every internal SubResource before any internal resource that references it"
        ),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
