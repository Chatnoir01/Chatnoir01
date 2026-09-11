#!/usr/bin/env python3
from __future__ import annotations

import json
import posixpath
import sys
import tempfile
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_canonical_resource_alias as alias
import civ1_external_resource_backing as backing

SCHEMA = "grand-bruxelles-civ1-external-resource-path-canonicality-v1"


def canonical_path_reason(path: str) -> str | None:
    if not path.startswith("res://"):
        return "external_resource_path_not_res_scheme"
    tail = path[6:]
    if not tail:
        return "external_resource_path_empty"
    if "\\" in tail:
        return "external_resource_path_backslash"
    if tail.startswith("/") or tail.endswith("/"):
        return "external_resource_path_boundary_slash"
    parts = tail.split("/")
    if any(part == "" for part in parts):
        return "external_resource_path_empty_segment"
    if any(part == "." for part in parts):
        return "external_resource_path_dot_segment"
    if any(part == ".." for part in parts):
        return "external_resource_path_parent_segment"
    normalized = posixpath.normpath(tail)
    if normalized != tail:
        return "external_resource_path_noncanonical_normalization"
    return None


def scene_path_conflicts(scene_text: str) -> list[dict[str, object]]:
    resources = skin.parse_resource_table(scene_text)
    conflicts: list[dict[str, object]] = []
    for (kind, rid), attrs in sorted(resources.items()):
        if kind != "ExtResource":
            continue
        path = attrs.get("path")
        if not isinstance(path, str):
            continue
        reason = canonical_path_reason(path)
        if reason:
            conflicts.append({
                "resource_id": rid,
                "path": path,
                "reason": reason,
            })
    return conflicts


def self_test() -> None:
    assert canonical_path_reason("res://assets/body.skin") is None
    assert canonical_path_reason("res://assets/body.material.tres") is None
    assert canonical_path_reason("res://assets/../assets/body.skin") == "external_resource_path_parent_segment"
    assert canonical_path_reason("res://assets/./body.skin") == "external_resource_path_dot_segment"
    assert canonical_path_reason("res://assets//body.skin") == "external_resource_path_empty_segment"
    assert canonical_path_reason("res://assets\\body.skin") == "external_resource_path_backslash"

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        game = root / "game"
        assets = root / "assets"
        game.mkdir(); assets.mkdir()
        for name in ("body.mesh", "body.skin", "body.material"):
            (assets / name).write_text("fixture-" + name, encoding="utf-8")
        canonical = '''
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
        scene.write_text(canonical, encoding="utf-8")
        assert scene_path_conflicts(canonical) == []

        detour = canonical.replace("res://assets/body.skin", "res://assets/../assets/body.skin")
        scene.write_text(detour, encoding="utf-8")
        old_backing = backing.scene_backing(scene, root)
        assert len(old_backing) == 1 and old_backing[0]["external_resource_backing_ready"], (
            "RED precondition: backing v5 resolves a single parent-segment detour to valid asset bytes"
        )
        assert alias.scene_alias_conflicts(scene, root) == [], (
            "RED precondition: alias v3 does not reject one noncanonical spelling when no second spelling is present"
        )
        conflicts = scene_path_conflicts(detour)
        assert conflicts == [{
            "resource_id": "Skin_body",
            "path": "res://assets/../assets/body.skin",
            "reason": "external_resource_path_parent_segment",
        }]


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_EXTERNAL_RESOURCE_PATH_CANONICALITY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_external_resource_path_canonicality.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for conflict in scene_path_conflicts(scene_path.read_text(encoding="utf-8")):
            conflicts.append({"scene": rel, **conflict})

    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_exact_canonical_res_external_resource_paths",
        "reachable_scene_count": len(scenes),
        "external_resource_path_canonicality_conflicts": conflicts,
        "external_resource_paths_canonical": not conflicts,
        "single_detour_path_evidence_accepted": False,
        "dot_segment_path_evidence_accepted": False,
        "empty_segment_path_evidence_accepted": False,
        "backslash_path_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "retain one canonical res:// path spelling per external Character resource"
            if not conflicts
            else "rewrite every external Character resource path to canonical res:// spelling before approval"
        ),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0 if not conflicts else 1


if __name__ == "__main__":
    raise SystemExit(main())
