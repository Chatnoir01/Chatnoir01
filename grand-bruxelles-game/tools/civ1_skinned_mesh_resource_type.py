#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-skinned-mesh-resource-type-v1"
PROCEDURAL_MESH_TYPES = {
    "PrimitiveMesh",
    "BoxMesh",
    "CapsuleMesh",
    "CylinderMesh",
    "PlaneMesh",
    "PrismMesh",
    "QuadMesh",
    "SphereMesh",
    "TextMesh",
    "TubeTrailMesh",
    "TorusMesh",
}


def skinned_mesh_resource_conflicts(scene_text: str) -> list[dict[str, object]]:
    resources = skin.parse_resource_table(scene_text)
    conflicts: list[dict[str, object]] = []
    for block in skin.parse_node_blocks(scene_text):
        attrs = block["attrs"]
        props = block["props"]
        assert isinstance(attrs, dict) and isinstance(props, dict)
        if attrs.get("type") != "MeshInstance3D" or "mesh" not in props:
            continue
        # Only police mesh resources that are actually presented as skinned
        # Character evidence. Decorative MeshInstance3D nodes are out of scope.
        if "skin" not in props or "skeleton" not in props:
            continue
        mesh_type = skin.declared_resource_type(resources, props.get("mesh"))
        if mesh_type != "ArrayMesh":
            conflicts.append({
                "mesh_path": skin.node_path(attrs),
                "mesh_resource_type": mesh_type,
                "reason": "skinned_authored_evidence_requires_array_mesh",
            })
    return conflicts


def fixture(mesh_type: str) -> str:
    return f'''\
[gd_scene load_steps=4 format=3]
[sub_resource type="{mesh_type}" id="Mesh_body"]
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
material_override = SubResource("Mat_body")
'''


def _legacy_accepts(scene_text: str) -> bool:
    evidence = skin.scene_integrity(scene_text)
    return bool(evidence and evidence[0].get("authored_skin_integrity_ready"))


def self_test() -> None:
    authored = fixture("ArrayMesh")
    assert _legacy_accepts(authored)
    assert skinned_mesh_resource_conflicts(authored) == []

    for mesh_type in sorted(PROCEDURAL_MESH_TYPES):
        procedural = fixture(mesh_type)
        assert _legacy_accepts(procedural), (
            f"regression precondition: authored-skin v3 must expose its legacy {mesh_type} false-positive"
        )
        conflicts = skinned_mesh_resource_conflicts(procedural)
        assert len(conflicts) == 1
        assert conflicts[0]["reason"] == "skinned_authored_evidence_requires_array_mesh"
        assert conflicts[0]["mesh_resource_type"] == mesh_type

    missing = fixture("ArrayMesh").replace(
        '[sub_resource type="ArrayMesh" id="Mesh_body"]\n', ''
    )
    assert skinned_mesh_resource_conflicts(missing)[0]["mesh_resource_type"] is None

    decorative = '''\
[gd_scene load_steps=2 format=3]
[sub_resource type="BoxMesh" id="Box"]
[node name="Main" type="Node3D"]
[node name="Prop" type="MeshInstance3D" parent="."]
mesh = SubResource("Box")
'''
    assert skinned_mesh_resource_conflicts(decorative) == []


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_SKINNED_MESH_RESOURCE_TYPE_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_skinned_mesh_resource_type.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        conflicts.extend({"scene": rel, **item} for item in skinned_mesh_resource_conflicts(scene_path.read_text(encoding="utf-8")))

    valid = not conflicts
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_skinned_mesh_resource_type",
        "reachable_scene_count": len(scenes),
        "skinned_mesh_resource_type_conflicts": conflicts,
        "skinned_mesh_resource_types_valid": valid,
        "primitive_mesh_authored_skin_evidence_accepted": False,
        "arraymesh_required_for_skinned_authored_evidence": True,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "replace procedural/missing skinned mesh evidence with a proven authored ArrayMesh before integrity approval" if not valid else "retain ArrayMesh resource-type gate before loaded-scene skinning approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
