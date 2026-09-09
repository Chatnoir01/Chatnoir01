#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-external-resource-backing-v3"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def ext_resource_backed(resources: dict[tuple[str, str], dict[str, str]], raw: object, project_root: Path) -> tuple[bool, str | None, str | None, str | None]:
    ref = skin.resource_ref(raw)
    if ref is None:
        return False, None, None, None
    kind, _rid = ref
    attrs = resources.get(ref)
    if attrs is None:
        return False, None, None, None
    declared_type = attrs.get("type")
    if kind == "SubResource":
        return True, None, None, declared_type
    path = attrs.get("path")
    if not path:
        return False, None, None, declared_type
    resolved = skin.res_to_file(project_root, path)
    if resolved is None or not resolved.is_file():
        return False, path, None, declared_type
    return True, path, sha256_file(resolved), declared_type


def scene_backing(scene_path: Path, project_root: Path) -> list[dict[str, object]]:
    text = scene_path.read_text(encoding="utf-8")
    structural = skin.scene_integrity(text)
    if not structural:
        return []
    blocks = skin.parse_node_blocks(text)
    resources = skin.parse_resource_table(text)
    props_by_path: dict[str, dict[str, object]] = {}
    for block in blocks:
        attrs = block["attrs"]
        props = block["props"]
        assert isinstance(attrs, dict) and isinstance(props, dict)
        if attrs.get("name"):
            props_by_path[skin.node_path(attrs)] = props

    out: list[dict[str, object]] = []
    for hierarchy in structural:
        mesh_details: list[dict[str, object]] = []
        all_backed = bool(hierarchy["authored_skin_integrity_ready"])
        used_external_types: dict[str, set[str]] = {}
        for mesh_path in hierarchy["complete_skin_bundle_paths"]:
            props = props_by_path.get(str(mesh_path), {})
            refs: list[tuple[str, object]] = [("mesh", props.get("mesh")), ("skin", props.get("skin"))]
            material_keys = sorted(k for k in props if k == "material_override" or k.startswith("surface_material_override/"))
            refs.extend((key, props.get(key)) for key in material_keys)
            ref_results = []
            mesh_backed = True
            for role, raw in refs:
                backed, path, fingerprint, declared_type = ext_resource_backed(resources, raw, project_root)
                mesh_backed = mesh_backed and backed
                if isinstance(path, str) and isinstance(declared_type, str):
                    used_external_types.setdefault(path, set()).add(declared_type)
                ref_results.append({
                    "role": role,
                    "raw": raw,
                    "external_path": path,
                    "declared_type": declared_type,
                    "sha256": fingerprint,
                    "backed": backed,
                })
            all_backed = all_backed and mesh_backed
            mesh_details.append({"path": mesh_path, "resources": ref_results, "all_resources_backed": mesh_backed})

        type_conflicts = [
            {"path": path, "declared_types": sorted(types)}
            for path, types in sorted(used_external_types.items())
            if len(types) > 1
        ]
        all_backed = all_backed and not type_conflicts
        out.append({
            "npc_agent_path": hierarchy["npc_agent_path"],
            "character_mount_path": hierarchy["character_mount_path"],
            "skeleton_path": hierarchy["skeleton_path"],
            "structural_skin_integrity_ready": hierarchy["authored_skin_integrity_ready"],
            "mesh_backing": mesh_details,
            "external_path_type_conflicts": type_conflicts,
            "external_path_type_consistent": not type_conflicts,
            "external_resource_backing_ready": all_backed,
        })
    return out


def fingerprints(evidence: list[dict[str, object]]) -> list[dict[str, str]]:
    unique: dict[str, str] = {}
    for hierarchy in evidence:
        for mesh in hierarchy.get("mesh_backing", []):
            assert isinstance(mesh, dict)
            for resource in mesh.get("resources", []):
                assert isinstance(resource, dict)
                path = resource.get("external_path")
                digest = resource.get("sha256")
                if isinstance(path, str) and isinstance(digest, str):
                    previous = unique.get(path)
                    if previous is not None and previous != digest:
                        raise AssertionError(f"same external path produced conflicting digests: {path}")
                    unique[path] = digest
    return [{"path": path, "sha256": unique[path]} for path in sorted(unique)]


def self_test() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        game = root / "game"
        assets = root / "assets"
        game.mkdir(); assets.mkdir()
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
        r = scene_backing(scene, root)
        assert len(r) == 1 and r[0]["external_resource_backing_ready"], "existing in-project external resources should pass backing preflight"
        assert r[0]["external_path_type_consistent"], "normal authored bundle must have one declared type per external path"
        first = fingerprints(r)
        assert len(first) == 3 and all(item["sha256"].startswith("sha256:") for item in first), "backed external resources must be content-addressed"

        (assets / "body.skin").write_text("fixture-mutated", encoding="utf-8")
        second = fingerprints(scene_backing(scene, root))
        before = {item["path"]: item["sha256"] for item in first}
        after = {item["path"]: item["sha256"] for item in second}
        assert before["res://assets/body.skin"] != after["res://assets/body.skin"], "resource mutation must change the sealed SHA-256"
        (assets / "body.skin").write_text("fixture", encoding="utf-8")

        missing = base.replace("res://assets/body.skin", "res://assets/missing.skin")
        scene.write_text(missing, encoding="utf-8")
        r = scene_backing(scene, root)
        assert len(r) == 1 and not r[0]["external_resource_backing_ready"], "typed-but-missing external Skin must fail closed"

        traversal = base.replace("res://assets/body.skin", "res://../outside.skin")
        scene.write_text(traversal, encoding="utf-8")
        r = scene_backing(scene, root)
        assert len(r) == 1 and not r[0]["external_resource_backing_ready"], "out-of-project external resource path must fail closed"

        type_alias = base.replace(
            '[ext_resource type="Skin" path="res://assets/body.skin" id="Skin_body"]',
            '[ext_resource type="Skin" path="res://assets/body.mesh" id="Skin_body"]',
        )
        scene.write_text(type_alias, encoding="utf-8")
        r = scene_backing(scene, root)
        assert len(r) == 1 and not r[0]["external_resource_backing_ready"], "one external file declared as both mesh and Skin must fail closed"
        assert not r[0]["external_path_type_consistent"]
        assert r[0]["external_path_type_conflicts"] == [{"path": "res://assets/body.mesh", "declared_types": ["ArrayMesh", "Skin"]}]


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_EXTERNAL_RESOURCE_BACKING_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_external_resource_backing.py MAIN_TSCN OUT", file=sys.stderr)
        return 2
    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    evidence: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        for item in scene_backing(scene_path, project_root):
            row = dict(item); row["scene"] = rel; evidence.append(row)
    ready = [e for e in evidence if e["external_resource_backing_ready"]]
    sealed = fingerprints(evidence)
    type_conflicts = [
        {"scene": e.get("scene"), "npc_agent_path": e.get("npc_agent_path"), **conflict}
        for e in evidence
        for conflict in e.get("external_path_type_conflicts", [])
        if isinstance(conflict, dict)
    ]
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_authored_skin_bundle_plus_in_project_external_resource_backing_plus_sha256_plus_path_type_consistency",
        "reachable_scene_count": len(scenes),
        "hierarchy_count": len(evidence),
        "backing_ready_count": len(ready),
        "hierarchies": evidence,
        "external_resource_fingerprints": sealed,
        "fingerprinted_external_resource_count": len(sealed),
        "external_path_type_conflicts": type_conflicts,
        "external_path_type_consistent": not type_conflicts,
        "typed_but_missing_external_resource_evidence_accepted": False,
        "out_of_project_external_resource_evidence_accepted": False,
        "unhashed_external_resource_evidence_accepted": False,
        "cross_type_same_path_evidence_accepted": False,
        "authored_external_resources_backed": bool(ready),
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "rerun Godot 4.7.1 loaded-scene probe only after structural skin integrity and resource backing both become ready; retain SHA-256 fingerprints and path/type consistency in the handoff" if ready else "runtime owner must provide a reachable authored skin bundle whose external mesh/Skin/material resources resolve to real in-project files with one declared Godot type per path",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
