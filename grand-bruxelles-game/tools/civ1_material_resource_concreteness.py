#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

from civ1_authored_skin_integrity import (
    declared_resource_type,
    parse_node_blocks,
    parse_resource_table,
    reachable_scenes,
)

SCHEMA = "grand-bruxelles-civ1-material-resource-concreteness-v1"
CONCRETE_MATERIAL_TYPES = {"StandardMaterial3D", "ORMMaterial3D", "ShaderMaterial"}
ABSTRACT_MATERIAL_TYPES = {"Material", "BaseMaterial3D"}


def inspect_scene(scene: str, scene_path: str = "<memory>") -> list[dict[str, object]]:
    resources = parse_resource_table(scene)
    conflicts: list[dict[str, object]] = []
    for block in parse_node_blocks(scene):
        attrs = block["attrs"]
        props = block["props"]
        assert isinstance(attrs, dict) and isinstance(props, dict)
        if attrs.get("type") != "MeshInstance3D":
            continue
        # Only skinned Character evidence is in scope. Decorative meshes are not
        # constrained by this gate.
        if "skin" not in props or "skeleton" not in props:
            continue
        material_keys = [
            key for key in props
            if key == "material_override" or key.startswith("surface_material_override/")
        ]
        for key in material_keys:
            declared_type = declared_resource_type(resources, props.get(key))
            if declared_type in ABSTRACT_MATERIAL_TYPES:
                conflicts.append({
                    "scene": scene_path,
                    "node": attrs.get("name"),
                    "property": key,
                    "declared_type": declared_type,
                    "reason": "abstract_material_type_used_as_renderable_character_evidence",
                })
            elif declared_type is not None and declared_type not in CONCRETE_MATERIAL_TYPES:
                conflicts.append({
                    "scene": scene_path,
                    "node": attrs.get("name"),
                    "property": key,
                    "declared_type": declared_type,
                    "reason": "unsupported_material_type_used_as_character_evidence",
                })
    return conflicts


def measure(main_tscn: Path) -> dict[str, object]:
    main_tscn = main_tscn.resolve()
    project_root = main_tscn.parent.parent
    scenes = reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        text = scene_path.read_text(encoding="utf-8")
        try:
            rel = scene_path.relative_to(project_root).as_posix()
        except ValueError:
            rel = str(scene_path)
        conflicts.extend(inspect_scene(text, rel))
    return {
        "schema": SCHEMA,
        "reachable_scene_count": len(scenes),
        "material_resource_concreteness_conflicts": conflicts,
        "abstract_material_evidence_accepted": bool(conflicts),
        "concrete_renderable_material_types_required": True,
        "material_resource_types_concrete": not conflicts,
        "accepted_concrete_material_types": sorted(CONCRETE_MATERIAL_TYPES),
        "rejected_abstract_material_types": sorted(ABSTRACT_MATERIAL_TYPES),
    }


def fixture(material_type: str) -> str:
    return f'''
[gd_scene load_steps=5 format=3]
[sub_resource type="ArrayMesh" id="Mesh_body"]
[sub_resource type="Skin" id="Skin_body"]
[sub_resource type="{material_type}" id="Mat_body"]
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


def legacy_material_accepts(scene: str) -> bool:
    # Mirrors authored-skin v3's broad material allow-list, preserving the RED
    # precondition explicitly rather than changing production code silently.
    legacy = {"StandardMaterial3D", "ORMMaterial3D", "ShaderMaterial", "BaseMaterial3D", "Material"}
    resources = parse_resource_table(scene)
    for block in parse_node_blocks(scene):
        attrs = block["attrs"]
        props = block["props"]
        assert isinstance(attrs, dict) and isinstance(props, dict)
        if attrs.get("type") != "MeshInstance3D":
            continue
        for key in props:
            if key == "material_override" or key.startswith("surface_material_override/"):
                if declared_resource_type(resources, props[key]) in legacy:
                    return True
    return False


def self_test() -> None:
    for abstract_type in sorted(ABSTRACT_MATERIAL_TYPES):
        scene = fixture(abstract_type)
        assert legacy_material_accepts(scene), (
            f"regression precondition: authored-skin v3 must accept {abstract_type} as material evidence"
        )
        conflicts = inspect_scene(scene)
        assert conflicts and conflicts[0]["declared_type"] == abstract_type, (
            f"{abstract_type} must fail closed as abstract material evidence"
        )

    for concrete_type in sorted(CONCRETE_MATERIAL_TYPES):
        scene = fixture(concrete_type)
        assert legacy_material_accepts(scene)
        assert inspect_scene(scene) == [], f"{concrete_type} must remain accepted"

    decorative = '''
[gd_scene load_steps=2 format=3]
[sub_resource type="Material" id="Mat_decor"]
[node name="Main" type="Node3D"]
[node name="Decoration" type="MeshInstance3D" parent="."]
material_override = SubResource("Mat_decor")
'''
    assert inspect_scene(decorative) == [], "unskinned decorative meshes are outside this gate"

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        game = root / "game"
        game.mkdir()
        main = game / "main.tscn"
        child = game / "civ1.tscn"
        unused = game / "unused.tscn"
        main.write_text('''
[gd_scene load_steps=2 format=3]
[ext_resource type="PackedScene" path="res://game/civ1.tscn" id="1_civ1"]
[node name="Main" type="Node3D"]
[node name="Civilian" parent="." instance=ExtResource("1_civ1")]
''', encoding="utf-8")
        child.write_text(fixture("Material"), encoding="utf-8")
        unused.write_text(fixture("StandardMaterial3D"), encoding="utf-8")
        receipt = measure(main)
        assert receipt["reachable_scene_count"] == 2
        assert receipt["abstract_material_evidence_accepted"] is True
        assert len(receipt["material_resource_concreteness_conflicts"]) == 1


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_MATERIAL_RESOURCE_CONCRETENESS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_material_resource_concreteness.py MAIN_TSCN OUT", file=sys.stderr)
        return 2
    receipt = measure(Path(sys.argv[1]))
    out = Path(sys.argv[2])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(receipt, sort_keys=True))
    return 1 if not receipt["material_resource_types_concrete"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
