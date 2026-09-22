#!/usr/bin/env python3
from __future__ import annotations

import tempfile
from pathlib import Path

import civ1_canonical_resource_alias as alias
import civ1_external_resource_backing as backing
import civ1_external_resource_path_canonicality as canonicality


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        game = root / "game"
        assets = root / "assets"
        game.mkdir(); assets.mkdir()
        for name in ("body.mesh", "body.skin", "body.material"):
            (assets / name).write_text("fixture-" + name, encoding="utf-8")
        scene_text = '''
[gd_scene load_steps=4 format=3]
[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]
[ext_resource type="Skin" path="res://assets/../assets/body.skin" id="Skin_body"]
[ext_resource type="StandardMaterial3D" path="res://assets/body.material" id="Mat_body"]
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../Skeleton3D")
mesh = ExtResource("Mesh_body")
skin = ExtResource("Skin_body")
material_override = ExtResource("Mat_body")
'''
        scene = game / "civ1.tscn"
        scene.write_text(scene_text, encoding="utf-8")
        legacy = backing.scene_backing(scene, root)
        assert len(legacy) == 1 and legacy[0]["external_resource_backing_ready"]
        assert alias.scene_alias_conflicts(scene, root) == []
        conflicts = canonicality.scene_path_conflicts(scene_text)
        assert len(conflicts) == 1
        assert conflicts[0]["resource_id"] == "Skin_body"
        assert conflicts[0]["reason"] == "external_resource_path_parent_segment"
        print("CIV1_EXTERNAL_RESOURCE_PATH_CANONICALITY_REGRESSION_GREEN legacy_false_positive=true canonical_gate_rejects=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
