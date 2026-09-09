#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_external_resource_backing as backing

SCHEMA = "grand-bruxelles-civ1-canonical-resource-alias-v1"


def scene_alias_conflicts(scene_path: Path, project_root: Path) -> list[dict[str, object]]:
    groups: dict[str, dict[str, set[str]]] = {}
    for hierarchy in backing.scene_backing(scene_path, project_root):
        for mesh in hierarchy.get("mesh_backing", []):
            if not isinstance(mesh, dict):
                continue
            for resource in mesh.get("resources", []):
                if not isinstance(resource, dict):
                    continue
                logical_path = resource.get("external_path")
                declared_type = resource.get("declared_type")
                if not isinstance(logical_path, str) or not isinstance(declared_type, str):
                    continue
                resolved = skin.res_to_file(project_root, logical_path)
                if resolved is None or not resolved.is_file():
                    continue
                canonical = resolved.resolve().relative_to(project_root.resolve()).as_posix()
                entry = groups.setdefault(canonical, {"logical_paths": set(), "declared_types": set()})
                entry["logical_paths"].add(logical_path)
                entry["declared_types"].add(declared_type)

    return [
        {
            "canonical_project_path": canonical,
            "logical_paths": sorted(values["logical_paths"]),
            "declared_types": sorted(values["declared_types"]),
        }
        for canonical, values in sorted(groups.items())
        if len(values["logical_paths"]) > 1
    ]


def self_test() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        game = root / "game"
        assets = root / "assets"
        game.mkdir()
        assets.mkdir()
        for name in ("body.mesh", "body.skin", "body.material"):
            (assets / name).write_text("fixture", encoding="utf-8")

        base = '''
[gd_scene load_steps=4 format=3]
[ext_resource type="ArrayMesh" path="res://assets/body.mesh" id="Mesh_body"]
[ext_resource type="Skin" path="res://assets/body.skin" id="Skin_body"]
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
        scene.write_text(base, encoding="utf-8")
        assert scene_alias_conflicts(scene, root) == [], "normal authored resource paths must be canonical-alias clean"

        alias = base.replace(
            '[ext_resource type="Skin" path="res://assets/body.skin" id="Skin_body"]',
            '[ext_resource type="Skin" path="res://assets/../assets/body.mesh" id="Skin_body"]',
        )
        scene.write_text(alias, encoding="utf-8")
        old = backing.scene_backing(scene, root)
        assert len(old) == 1 and old[0]["external_resource_backing_ready"], (
            "regression precondition: v5 path-string guard should reproduce the canonical-alias false positive"
        )
        conflicts = scene_alias_conflicts(scene, root)
        assert conflicts == [{
            "canonical_project_path": "assets/body.mesh",
            "logical_paths": ["res://assets/../assets/body.mesh", "res://assets/body.mesh"],
            "declared_types": ["ArrayMesh", "Skin"],
        }], "two lexical res:// paths resolving to one physical asset must fail closed"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_CANONICAL_RESOURCE_ALIAS_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_canonical_resource_alias.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for conflict in scene_alias_conflicts(scene_path, project_root):
            conflicts.append({"scene": rel, **conflict})

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_authored_skin_bundle_plus_canonical_resolved_external_resource_identity",
        "reachable_scene_count": len(scenes),
        "canonical_alias_conflicts": conflicts,
        "canonical_external_resource_identity_consistent": not conflicts,
        "canonical_alias_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "remove lexical/symlink aliases so every physical authored external resource has one canonical res:// identity"
            if conflicts
            else "retain canonical external resource identity gate before any Godot loaded-scene authored-character approval"
        ),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
