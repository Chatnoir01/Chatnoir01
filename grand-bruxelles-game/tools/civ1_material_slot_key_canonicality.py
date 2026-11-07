#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-material-slot-key-canonicality-v1"
SURFACE_KEY_RE = re.compile(r"^surface_material_override/(0|[1-9][0-9]*)$")


def material_slot_conflicts(scene_text: str) -> list[dict[str, object]]:
    conflicts: list[dict[str, object]] = []
    for block in skin.parse_node_blocks(scene_text):
        attrs = block["attrs"]
        props = block["props"]
        assert isinstance(attrs, dict) and isinstance(props, dict)
        if attrs.get("type") != "MeshInstance3D" or "name" not in attrs:
            continue
        mesh_path = skin.node_path(attrs)
        for key in props:
            if key == "material_override":
                continue
            if not key.startswith("surface_material_override/"):
                continue
            if not SURFACE_KEY_RE.fullmatch(key):
                conflicts.append({
                    "mesh_path": mesh_path,
                    "property": key,
                    "reason": "surface_material_override_key_not_canonical_numeric_index",
                })
    return conflicts


def fixture(material_key: str) -> str:
    return f'''\
[gd_scene load_steps=4 format=3]
[sub_resource type="ArrayMesh" id="Mesh_body"]
[sub_resource type="Skin" id="Skin_body"]
[sub_resource type="StandardMaterial3D" id="Mat_body"]
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../Skeleton3D")
mesh = SubResource("Mesh_body")
skin = SubResource("Skin_body")
{material_key} = SubResource("Mat_body")
'''


def _legacy_accepts(scene_text: str) -> bool:
    evidence = skin.scene_integrity(scene_text)
    return bool(evidence and evidence[0].get("authored_skin_integrity_ready"))


def self_test() -> None:
    valid_zero = fixture("surface_material_override/0")
    assert material_slot_conflicts(valid_zero) == []
    assert _legacy_accepts(valid_zero)

    valid_multi = fixture("surface_material_override/12")
    assert material_slot_conflicts(valid_multi) == []
    assert _legacy_accepts(valid_multi)

    forged_name = fixture("surface_material_override/fake")
    assert _legacy_accepts(forged_name), "regression precondition: authored-skin v3 accepts nonnumeric material slot key"
    conflicts = material_slot_conflicts(forged_name)
    assert len(conflicts) == 1 and conflicts[0]["reason"] == "surface_material_override_key_not_canonical_numeric_index"

    forged_negative = fixture("surface_material_override/-1")
    assert _legacy_accepts(forged_negative), "regression precondition: authored-skin v3 accepts negative material slot key"
    assert len(material_slot_conflicts(forged_negative)) == 1

    forged_leading_zero = fixture("surface_material_override/01")
    assert _legacy_accepts(forged_leading_zero), "regression precondition: authored-skin v3 accepts noncanonical leading-zero slot key"
    assert len(material_slot_conflicts(forged_leading_zero)) == 1

    direct = fixture("material_override")
    assert material_slot_conflicts(direct) == []
    assert _legacy_accepts(direct)


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_MATERIAL_SLOT_KEY_CANONICALITY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_material_slot_key_canonicality.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        conflicts.extend({"scene": rel, **item} for item in material_slot_conflicts(scene_path.read_text(encoding="utf-8")))

    canonical = not conflicts
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_canonical_mesh_material_slot_property_keys",
        "reachable_scene_count": len(scenes),
        "material_slot_key_conflicts": conflicts,
        "material_slot_keys_canonical": canonical,
        "nonnumeric_material_slot_evidence_accepted": False,
        "negative_material_slot_evidence_accepted": False,
        "leading_zero_material_slot_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "canonicalize MeshInstance3D surface_material_override/<index> keys before authored-skin evidence can be trusted" if not canonical else "retain material-slot key gate before loaded-scene material approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
