#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
import tempfile
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-authored-skin-integrity-v3"
NODE_RE = re.compile(r'^\s*\[node\s+(.+?)\]\s*$')
EXT_RE = re.compile(r'^\s*\[ext_resource\s+(.+?)\]\s*$')
SUB_RE = re.compile(r'^\s*\[sub_resource\s+(.+?)\]\s*$')
ATTR_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"')
INSTANCE_RE = re.compile(r'\binstance=ExtResource\("([^"]+)"\)')
NODEPATH_RE = re.compile(r'^NodePath\("([^"]+)"\)$')
RESOURCE_RE = re.compile(r'^(ExtResource|SubResource)\("([^"]+)"\)$')
MESH_TYPES = {"ArrayMesh", "PrimitiveMesh", "BoxMesh", "CapsuleMesh", "CylinderMesh", "PlaneMesh", "PrismMesh", "QuadMesh", "SphereMesh", "TextMesh", "TubeTrailMesh"}
MATERIAL_TYPES = {"StandardMaterial3D", "ORMMaterial3D", "ShaderMaterial", "BaseMaterial3D", "Material"}


def node_path(attrs: dict[str, str]) -> str:
    parent = attrs.get("parent", ".")
    name = attrs["name"]
    return name if parent in ("", ".") else f"{parent}/{name}".strip("/")


def parse_node_blocks(scene: str) -> list[dict[str, object]]:
    blocks: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    for line in scene.splitlines():
        match = NODE_RE.match(line)
        if match:
            attrs = dict(ATTR_RE.findall(match.group(1)))
            inst = INSTANCE_RE.search(match.group(1))
            if inst:
                attrs["instance"] = inst.group(1)
            current = {"attrs": attrs, "props": {}}
            blocks.append(current)
            continue
        if line.lstrip().startswith("["):
            current = None
            continue
        if current is None or not line:
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        props = current["props"]
        assert isinstance(props, dict)
        props[key.strip()] = value.strip()
    return blocks


def _legacy_parse_node_blocks(scene: str) -> list[dict[str, object]]:
    blocks: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    for line in scene.splitlines():
        match = NODE_RE.match(line)
        if match:
            attrs = dict(ATTR_RE.findall(match.group(1)))
            inst = INSTANCE_RE.search(match.group(1))
            if inst:
                attrs["instance"] = inst.group(1)
            current = {"attrs": attrs, "props": {}}
            blocks.append(current)
            continue
        if current is None or not line or line.lstrip().startswith("["):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        props = current["props"]
        assert isinstance(props, dict)
        props[key.strip()] = value.strip()
    return blocks


def parse_resource_table(scene: str) -> dict[tuple[str, str], dict[str, str]]:
    resources: dict[tuple[str, str], dict[str, str]] = {}
    for line in scene.splitlines():
        match = EXT_RE.match(line)
        kind = "ExtResource"
        if not match:
            match = SUB_RE.match(line)
            kind = "SubResource"
        if not match:
            continue
        attrs = dict(ATTR_RE.findall(match.group(1)))
        rid = attrs.get("id")
        if rid:
            resources[(kind, rid)] = attrs
    return resources


def resource_ref(raw: object) -> tuple[str, str] | None:
    if not isinstance(raw, str):
        return None
    match = RESOURCE_RE.match(raw)
    if not match:
        return None
    return match.group(1), match.group(2)


def declared_resource_type(resources: dict[tuple[str, str], dict[str, str]], raw: object) -> str | None:
    ref = resource_ref(raw)
    if ref is None:
        return None
    attrs = resources.get(ref)
    return attrs.get("type") if attrs else None


def parse_packed_resources(scene: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for (kind, rid), attrs in parse_resource_table(scene).items():
        if kind == "ExtResource" and attrs.get("type") == "PackedScene" and attrs.get("path"):
            out[rid] = attrs["path"]
    return out


def res_to_file(root: Path, resource: str) -> Path | None:
    if not resource.startswith("res://"):
        return None
    candidate = (root / resource[6:]).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        return None
    return candidate


def reachable_scenes(main_tscn: Path, project_root: Path) -> list[Path]:
    pending = [main_tscn.resolve()]
    seen: set[Path] = set()
    result: list[Path] = []
    while pending:
        path = pending.pop()
        if path in seen or not path.is_file():
            continue
        seen.add(path)
        try:
            path.relative_to(project_root.resolve())
        except ValueError:
            continue
        result.append(path)
        text = path.read_text(encoding="utf-8")
        packed = parse_packed_resources(text)
        for block in parse_node_blocks(text):
            attrs = block["attrs"]
            assert isinstance(attrs, dict)
            rid = attrs.get("instance")
            if rid and rid in packed:
                child = res_to_file(project_root, packed[rid])
                if child is not None and child.suffix == ".tscn":
                    pending.append(child)
    return result


def resolve_nodepath(owner_path: str, raw: str) -> str | None:
    match = NODEPATH_RE.match(raw)
    if not match:
        return None
    target = match.group(1)
    if target.startswith("/"):
        return target.strip("/")
    parts = owner_path.split("/")
    for part in target.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                return None
            parts.pop()
        else:
            parts.append(part)
    return "/".join(parts)


def _scene_integrity_with_blocks(scene: str, blocks: list[dict[str, object]]) -> list[dict[str, object]]:
    resources = parse_resource_table(scene)
    nodes: dict[str, dict[str, object]] = {}
    for block in blocks:
        attrs = block["attrs"]
        assert isinstance(attrs, dict)
        if "name" in attrs:
            nodes[node_path(attrs)] = block

    results: list[dict[str, object]] = []
    for mount_path, mount_block in nodes.items():
        mount_attrs = mount_block["attrs"]
        assert isinstance(mount_attrs, dict)
        if mount_attrs.get("name") != "CharacterMount" or mount_attrs.get("type") != "Node3D":
            continue
        agent_path = mount_attrs.get("parent", "")
        agent = nodes.get(agent_path)
        if not agent:
            continue
        agent_attrs = agent["attrs"]
        assert isinstance(agent_attrs, dict)
        if agent_attrs.get("name") != "NpcAgent" or agent_attrs.get("type") != "CharacterBody3D":
            continue
        prefix = mount_path + "/"
        skeleton_paths = [p for p, block in nodes.items() if p.startswith(prefix) and isinstance(block["attrs"], dict) and block["attrs"].get("type") == "Skeleton3D"]
        for skeleton_path in skeleton_paths:
            bound_meshes: list[str] = []
            complete_meshes: list[str] = []
            mesh_details: list[dict[str, object]] = []
            for mesh_path, mesh_block in nodes.items():
                attrs = mesh_block["attrs"]
                props = mesh_block["props"]
                assert isinstance(attrs, dict) and isinstance(props, dict)
                if attrs.get("type") != "MeshInstance3D" or not mesh_path.startswith(prefix):
                    continue
                skeleton_ok = isinstance(props.get("skeleton"), str) and resolve_nodepath(mesh_path, props["skeleton"]) == skeleton_path
                if not skeleton_ok:
                    continue
                bound_meshes.append(mesh_path)
                mesh_type = declared_resource_type(resources, props.get("mesh"))
                skin_type = declared_resource_type(resources, props.get("skin"))
                material_keys = [k for k in props if k == "material_override" or k.startswith("surface_material_override/")]
                material_types = [declared_resource_type(resources, props[k]) for k in material_keys]
                mesh_resource_ok = mesh_type in MESH_TYPES
                skin_resource_ok = skin_type == "Skin"
                material_resource_ok = any(t in MATERIAL_TYPES for t in material_types)
                complete = mesh_resource_ok and skin_resource_ok and material_resource_ok
                if complete:
                    complete_meshes.append(mesh_path)
                mesh_details.append({
                    "path": mesh_path,
                    "mesh_resource_type": mesh_type,
                    "skin_resource_type": skin_type,
                    "material_resource_types": sorted(t for t in material_types if t),
                    "mesh_resource_declared": mesh_resource_ok,
                    "skin_resource_declared": skin_resource_ok,
                    "material_resource_declared": material_resource_ok,
                    "structural_skin_bundle_ready": complete,
                })
            results.append({
                "npc_agent_path": agent_path,
                "character_mount_path": mount_path,
                "skeleton_path": skeleton_path,
                "skinned_mesh_paths": sorted(bound_meshes),
                "complete_skin_bundle_paths": sorted(complete_meshes),
                "mesh_details": mesh_details,
                "skinned_mesh_binding_present": bool(bound_meshes),
                "authored_skin_integrity_ready": bool(complete_meshes),
            })
    return results


def scene_integrity(scene: str) -> list[dict[str, object]]:
    return _scene_integrity_with_blocks(scene, parse_node_blocks(scene))


def _legacy_scene_integrity(scene: str) -> list[dict[str, object]]:
    return _scene_integrity_with_blocks(scene, _legacy_parse_node_blocks(scene))


def fixture_base() -> str:
    return '''
[gd_scene load_steps=4 format=3]
[sub_resource type="ArrayMesh" id="Mesh_body"]
[sub_resource type="Skin" id="Skin_body"]
[sub_resource type="StandardMaterial3D" id="Mat_body"]
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
'''


def self_test() -> None:
    empty = fixture_base()
    r = scene_integrity(empty)
    assert len(r) == 1 and not r[0]["authored_skin_integrity_ready"], "empty skeleton must fail closed"

    phantom = empty + '''
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../Skeleton3D")
mesh = SubResource("MissingMesh")
skin = SubResource("MissingSkin")
material_override = SubResource("MissingMaterial")
'''
    r = scene_integrity(phantom)
    assert r[0]["skinned_mesh_binding_present"] and not r[0]["authored_skin_integrity_ready"], "phantom resource ids must fail closed"

    no_skin = empty + '''
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../Skeleton3D")
mesh = SubResource("Mesh_body")
material_override = SubResource("Mat_body")
'''
    r = scene_integrity(no_skin)
    assert not r[0]["authored_skin_integrity_ready"], "mesh without declared Skin resource must fail closed"

    wrong_skin_type = empty + '''
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../Skeleton3D")
mesh = SubResource("Mesh_body")
skin = SubResource("Mat_body")
material_override = SubResource("Mat_body")
'''
    r = scene_integrity(wrong_skin_type)
    assert not r[0]["authored_skin_integrity_ready"], "non-Skin resource in skin property must fail closed"

    wrong_skeleton = empty + '''
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../WrongSkeleton")
mesh = SubResource("Mesh_body")
skin = SubResource("Skin_body")
material_override = SubResource("Mat_body")
'''
    r = scene_integrity(wrong_skeleton)
    assert not r[0]["skinned_mesh_binding_present"], "wrong skeleton path must fail closed"

    valid = empty + '''
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../Skeleton3D")
mesh = SubResource("Mesh_body")
skin = SubResource("Skin_body")
material_override = SubResource("Mat_body")
'''
    r = scene_integrity(valid)
    assert r[0]["authored_skin_integrity_ready"], "declared mesh+Skin+material bound to expected skeleton should pass structural preflight"

    cross_section_forged = empty + '''
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../Skeleton3D")
[sub_resource type="Resource" id="Carrier"]
mesh = SubResource("Mesh_body")
skin = SubResource("Skin_body")
material_override = SubResource("Mat_body")
'''
    legacy = _legacy_scene_integrity(cross_section_forged)
    assert legacy[0]["authored_skin_integrity_ready"], "regression precondition: legacy parser must accept cross-section property bleed"
    r = scene_integrity(cross_section_forged)
    assert r[0]["skinned_mesh_binding_present"] and not r[0]["authored_skin_integrity_ready"], "properties after a non-node section header must never belong to the preceding node"

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
        child.write_text(valid, encoding="utf-8")
        unused.write_text(valid, encoding="utf-8")
        paths = reachable_scenes(main, root)
        assert child.resolve() in paths and unused.resolve() not in paths, "unused scene must not supply integrity evidence"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_AUTHORED_SKIN_INTEGRITY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_authored_skin_integrity.py MAIN_TSCN OUT", file=sys.stderr)
        return 2
    main_tscn = Path(sys.argv[1]).resolve()
    out = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = reachable_scenes(main_tscn, project_root)
    evidence: list[dict[str, object]] = []
    scene_names: list[str] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        scene_names.append(rel)
        for item in scene_integrity(scene_path.read_text(encoding="utf-8")):
            enriched = dict(item)
            enriched["scene"] = rel
            evidence.append(enriched)
    ready = [item for item in evidence if item["authored_skin_integrity_ready"]]
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_exact_node_block_boundaries_plus_exact_skeleton_path_plus_declared_mesh_skin_material_resources",
        "reachable_scene_count": len(scene_names),
        "reachable_scenes": scene_names,
        "hierarchy_count": len(evidence),
        "integrity_ready_count": len(ready),
        "hierarchies": evidence,
        "empty_skeleton_evidence_accepted": False,
        "phantom_resource_evidence_accepted": False,
        "missing_skin_resource_evidence_accepted": False,
        "wrong_skin_type_evidence_accepted": False,
        "wrong_skeleton_evidence_accepted": False,
        "cross_section_property_bleed_evidence_accepted": False,
        "node_block_boundaries_exact": True,
        "authored_skin_integrity_ready": bool(ready),
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "rerun Godot 4.7.1 loaded-scene probe and verify imported Skeleton3D bone count, Skin binds/weights, materials and animation state"
            if ready else
            "runtime owner must provide a reachable authored CIV-1 hierarchy with MeshInstance3D bound to the expected Skeleton3D and declared mesh, Skin and material resources"
        ),
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
