#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
import tempfile
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-authored-skin-integrity-v1"
NODE_RE = re.compile(r'^\s*\[node\s+(.+?)\]\s*$')
EXT_RE = re.compile(r'^\s*\[ext_resource\s+(.+?)\]\s*$')
ATTR_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"')
INSTANCE_RE = re.compile(r'\binstance=ExtResource\("([^"]+)"\)')
NODEPATH_RE = re.compile(r'^NodePath\("([^"]+)"\)$')
RESOURCE_RE = re.compile(r'^(?:ExtResource|SubResource)\("([^"]+)"\)$')


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
        if current is None or not line or line.lstrip().startswith("["):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        props = current["props"]
        assert isinstance(props, dict)
        props[key.strip()] = value.strip()
    return blocks


def parse_packed_resources(scene: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in scene.splitlines():
        match = EXT_RE.match(line)
        if not match:
            continue
        attrs = dict(ATTR_RE.findall(match.group(1)))
        if attrs.get("type") == "PackedScene" and attrs.get("id") and attrs.get("path"):
            out[attrs["id"]] = attrs["path"]
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
            if not rid or rid not in packed:
                continue
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


def scene_integrity(scene: str) -> list[dict[str, object]]:
    blocks = parse_node_blocks(scene)
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
        skeleton_paths = [
            p for p, block in nodes.items()
            if p.startswith(prefix)
            and isinstance(block["attrs"], dict)
            and block["attrs"].get("type") == "Skeleton3D"
        ]
        for skeleton_path in skeleton_paths:
            bound_meshes: list[str] = []
            material_meshes: list[str] = []
            for mesh_path, mesh_block in nodes.items():
                attrs = mesh_block["attrs"]
                props = mesh_block["props"]
                assert isinstance(attrs, dict) and isinstance(props, dict)
                if attrs.get("type") != "MeshInstance3D" or not mesh_path.startswith(prefix):
                    continue
                skeleton_ref = props.get("skeleton")
                if isinstance(skeleton_ref, str) and resolve_nodepath(mesh_path, skeleton_ref) == skeleton_path:
                    bound_meshes.append(mesh_path)
                    material_keys = [k for k in props if k == "material_override" or k.startswith("surface_material_override/")]
                    if any(isinstance(props[k], str) and RESOURCE_RE.match(props[k]) for k in material_keys):
                        material_meshes.append(mesh_path)
            results.append({
                "npc_agent_path": agent_path,
                "character_mount_path": mount_path,
                "skeleton_path": skeleton_path,
                "skinned_mesh_paths": sorted(bound_meshes),
                "material_bound_mesh_paths": sorted(material_meshes),
                "skinned_mesh_binding_present": bool(bound_meshes),
                "material_binding_present": bool(material_meshes),
                "authored_skin_integrity_ready": bool(bound_meshes and material_meshes),
            })
    return results


def self_test() -> None:
    empty = '''
[node name="Main" type="Node3D"]
[node name="NpcAgent" type="CharacterBody3D" parent="."]
[node name="CharacterMount" type="Node3D" parent="NpcAgent"]
[node name="Skeleton3D" type="Skeleton3D" parent="NpcAgent/CharacterMount"]
'''
    r = scene_integrity(empty)
    assert len(r) == 1 and not r[0]["authored_skin_integrity_ready"], "empty skeleton must fail closed"

    unbound = empty + '''
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../WrongSkeleton")
material_override = ExtResource("1_mat")
'''
    r = scene_integrity(unbound)
    assert not r[0]["skinned_mesh_binding_present"], "mesh bound to wrong skeleton must fail closed"

    no_material = empty + '''
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../Skeleton3D")
'''
    r = scene_integrity(no_material)
    assert r[0]["skinned_mesh_binding_present"] and not r[0]["material_binding_present"]
    assert not r[0]["authored_skin_integrity_ready"], "skin without material must fail closed"

    valid = empty + '''
[node name="Body" type="MeshInstance3D" parent="NpcAgent/CharacterMount"]
skeleton = NodePath("../Skeleton3D")
material_override = ExtResource("1_mat")
'''
    r = scene_integrity(valid)
    assert r[0]["authored_skin_integrity_ready"], "bound skinned mesh with material should pass structural integrity"

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
        "evidence_mode": "reachable_tscn_node_blocks_plus_explicit_skeleton_and_material_binding",
        "reachable_scene_count": len(scene_names),
        "reachable_scenes": scene_names,
        "hierarchy_count": len(evidence),
        "integrity_ready_count": len(ready),
        "hierarchies": evidence,
        "empty_skeleton_evidence_accepted": False,
        "unbound_mesh_evidence_accepted": False,
        "materialless_mesh_evidence_accepted": False,
        "authored_skin_integrity_ready": bool(ready),
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "rerun Godot 4.7.1 loaded-scene probe and validate imported Skin/bone/material resources"
            if ready else
            "runtime owner must provide a reachable authored CIV-1 hierarchy with an explicitly Skeleton3D-bound MeshInstance3D and material binding"
        ),
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
