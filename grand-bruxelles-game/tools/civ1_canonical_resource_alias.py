#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_external_resource_backing as backing

SCHEMA = "grand-bruxelles-civ1-canonical-resource-alias-v3"


def _resource_identity(resolved: Path) -> tuple[int, int]:
    stat = resolved.stat()
    return (int(stat.st_dev), int(stat.st_ino))


def scene_alias_conflicts(scene_path: Path, project_root: Path) -> list[dict[str, object]]:
    canonical_groups: dict[str, dict[str, set[str]]] = {}
    physical_groups: dict[tuple[int, int], dict[str, set[str]]] = {}
    content_groups: dict[str, dict[str, set[str]]] = {}
    canonical_root = project_root.resolve()

    for hierarchy in backing.scene_backing(scene_path, project_root):
        for mesh in hierarchy.get("mesh_backing", []):
            if not isinstance(mesh, dict):
                continue
            for resource in mesh.get("resources", []):
                if not isinstance(resource, dict):
                    continue
                logical_path = resource.get("external_path")
                declared_type = resource.get("declared_type")
                digest = resource.get("sha256")
                if not isinstance(logical_path, str) or not isinstance(declared_type, str):
                    continue
                resolved = skin.res_to_file(project_root, logical_path)
                if resolved is None or not resolved.is_file():
                    continue
                canonical = resolved.resolve().relative_to(canonical_root).as_posix()
                canonical_entry = canonical_groups.setdefault(
                    canonical,
                    {"logical_paths": set(), "declared_types": set()},
                )
                canonical_entry["logical_paths"].add(logical_path)
                canonical_entry["declared_types"].add(declared_type)

                identity = _resource_identity(resolved.resolve())
                physical_entry = physical_groups.setdefault(
                    identity,
                    {"canonical_paths": set(), "logical_paths": set(), "declared_types": set()},
                )
                physical_entry["canonical_paths"].add(canonical)
                physical_entry["logical_paths"].add(logical_path)
                physical_entry["declared_types"].add(declared_type)

                if isinstance(digest, str):
                    content_entry = content_groups.setdefault(
                        digest,
                        {"canonical_paths": set(), "logical_paths": set(), "declared_types": set()},
                    )
                    content_entry["canonical_paths"].add(canonical)
                    content_entry["logical_paths"].add(logical_path)
                    content_entry["declared_types"].add(declared_type)

    conflicts: list[dict[str, object]] = []
    for canonical, values in sorted(canonical_groups.items()):
        if len(values["logical_paths"]) <= 1:
            continue
        conflicts.append({
            "conflict_kind": "canonical_path_alias",
            "canonical_project_paths": [canonical],
            "logical_paths": sorted(values["logical_paths"]),
            "declared_types": sorted(values["declared_types"]),
        })

    for identity, values in sorted(physical_groups.items()):
        if len(values["canonical_paths"]) <= 1:
            continue
        conflicts.append({
            "conflict_kind": "physical_file_alias",
            "canonical_project_paths": sorted(values["canonical_paths"]),
            "logical_paths": sorted(values["logical_paths"]),
            "declared_types": sorted(values["declared_types"]),
            "physical_identity": {"device": identity[0], "inode": identity[1]},
        })

    for digest, values in sorted(content_groups.items()):
        if len(values["canonical_paths"]) <= 1 or len(values["declared_types"]) <= 1:
            continue
        conflicts.append({
            "conflict_kind": "cross_type_content_alias",
            "canonical_project_paths": sorted(values["canonical_paths"]),
            "logical_paths": sorted(values["logical_paths"]),
            "declared_types": sorted(values["declared_types"]),
            "sha256": digest,
        })

    return conflicts


def self_test() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        game = root / "game"
        assets = root / "assets"
        game.mkdir()
        assets.mkdir()
        (assets / "body.mesh").write_text("mesh-fixture", encoding="utf-8")
        (assets / "body.skin").write_text("skin-fixture", encoding="utf-8")
        (assets / "body.material").write_text("material-fixture", encoding="utf-8")

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
        assert scene_alias_conflicts(scene, root) == [], "normal authored resource paths must be alias clean"

        lexical_alias = base.replace(
            '[ext_resource type="Skin" path="res://assets/body.skin" id="Skin_body"]',
            '[ext_resource type="Skin" path="res://assets/../assets/body.mesh" id="Skin_body"]',
        )
        scene.write_text(lexical_alias, encoding="utf-8")
        old = backing.scene_backing(scene, root)
        assert len(old) == 1 and old[0]["external_resource_backing_ready"], (
            "regression precondition: v5 path-string guard should reproduce the canonical-alias false positive"
        )
        conflicts = scene_alias_conflicts(scene, root)
        assert any(c["conflict_kind"] == "canonical_path_alias" for c in conflicts), (
            "two lexical res:// paths resolving to one canonical asset must fail closed"
        )

        hardlink = assets / "body.skin.hardlink"
        os.link(assets / "body.mesh", hardlink)
        hardlink_alias = base.replace(
            '[ext_resource type="Skin" path="res://assets/body.skin" id="Skin_body"]',
            '[ext_resource type="Skin" path="res://assets/body.skin.hardlink" id="Skin_body"]',
        )
        scene.write_text(hardlink_alias, encoding="utf-8")
        old = backing.scene_backing(scene, root)
        assert len(old) == 1 and old[0]["external_resource_backing_ready"], (
            "regression precondition: v5 and canonical-path resolution should accept distinct hardlink paths"
        )
        conflicts = scene_alias_conflicts(scene, root)
        assert any(c["conflict_kind"] == "physical_file_alias" for c in conflicts), (
            "distinct canonical paths backed by one physical inode must fail closed"
        )

        copied_skin = assets / "body.skin.copy"
        copied_skin.write_bytes((assets / "body.mesh").read_bytes())
        content_alias = base.replace(
            '[ext_resource type="Skin" path="res://assets/body.skin" id="Skin_body"]',
            '[ext_resource type="Skin" path="res://assets/body.skin.copy" id="Skin_body"]',
        )
        scene.write_text(content_alias, encoding="utf-8")
        old = backing.scene_backing(scene, root)
        assert len(old) == 1 and old[0]["external_resource_backing_ready"], (
            "regression precondition: v5 must reproduce the copied-byte cross-type false positive"
        )
        assert (assets / "body.mesh").resolve() != copied_skin.resolve()
        assert _resource_identity(assets / "body.mesh") != _resource_identity(copied_skin)
        conflicts = scene_alias_conflicts(scene, root)
        content_conflicts = [c for c in conflicts if c["conflict_kind"] == "cross_type_content_alias"]
        assert len(content_conflicts) == 1, "byte-identical resources declared under different Godot types must fail closed"
        assert content_conflicts[0]["canonical_project_paths"] == ["assets/body.mesh", "assets/body.skin.copy"]
        assert content_conflicts[0]["declared_types"] == ["ArrayMesh", "Skin"]
        assert str(content_conflicts[0]["sha256"]).startswith("sha256:")

        same_type_copy = assets / "body.mesh.copy"
        same_type_copy.write_bytes((assets / "body.mesh").read_bytes())
        same_type_scene = base.replace(
            '[ext_resource type="Skin" path="res://assets/body.skin" id="Skin_body"]',
            '[ext_resource type="ArrayMesh" path="res://assets/body.mesh.copy" id="Skin_body"]',
        )
        scene.write_text(same_type_scene, encoding="utf-8")
        conflicts = scene_alias_conflicts(scene, root)
        assert not any(c["conflict_kind"] == "cross_type_content_alias" for c in conflicts), (
            "same-content resources with one declared Godot type must not be rejected by the cross-type guard"
        )


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
        "evidence_mode": "reachable_authored_skin_bundle_plus_canonical_path_physical_file_and_cross_type_content_identity",
        "reachable_scene_count": len(scenes),
        "canonical_alias_conflicts": conflicts,
        "canonical_external_resource_identity_consistent": not conflicts,
        "canonical_alias_evidence_accepted": False,
        "hardlink_alias_evidence_accepted": False,
        "cross_type_content_alias_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "remove lexical, physical, or cross-type byte-content aliases so every authored resource has one unambiguous Godot identity"
            if conflicts
            else "retain canonical, physical, and cross-type content identity gates before Godot loaded-scene authored-character approval"
        ),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
