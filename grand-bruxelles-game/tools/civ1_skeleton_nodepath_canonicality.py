#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin

SCHEMA = "grand-bruxelles-civ1-skeleton-nodepath-canonicality-v1"
NODEPATH_LITERAL_RE = re.compile(r'^NodePath\(("(?:\\.|[^"\\])*")\)$')


def decode_nodepath_literal(raw: object) -> str | None:
    if not isinstance(raw, str):
        return None
    match = NODEPATH_LITERAL_RE.match(raw)
    if not match:
        return None
    try:
        value = json.loads(match.group(1))
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, str) else None


def resolve_decoded_nodepath(owner_path: str, target: str) -> str | None:
    if target.startswith("/"):
        return target.strip("/")
    parts = owner_path.split("/") if owner_path else []
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


def canonical_relative_nodepath(owner_path: str, target_path: str) -> str:
    owner = owner_path.split("/") if owner_path else []
    target = target_path.split("/") if target_path else []
    common = 0
    while common < min(len(owner), len(target)) and owner[common] == target[common]:
        common += 1
    parts = [".."] * (len(owner) - common) + target[common:]
    return "/".join(parts) if parts else "."


def skeleton_nodepath_conflicts(scene_text: str) -> list[dict[str, object]]:
    blocks = skin.parse_node_blocks(scene_text)
    conflicts: list[dict[str, object]] = []
    for block in blocks:
        attrs = block["attrs"]
        props = block["props"]
        assert isinstance(attrs, dict) and isinstance(props, dict)
        if attrs.get("type") != "MeshInstance3D" or "name" not in attrs or "skeleton" not in props:
            continue
        owner_path = skin.node_path(attrs)
        raw = props.get("skeleton")
        decoded = decode_nodepath_literal(raw)
        if decoded is None:
            conflicts.append({
                "mesh_path": owner_path,
                "raw_skeleton": raw,
                "reason": "skeleton_nodepath_literal_not_strictly_decodable",
            })
            continue
        if decoded.startswith("/"):
            conflicts.append({
                "mesh_path": owner_path,
                "raw_skeleton": raw,
                "decoded_skeleton": decoded,
                "reason": "absolute_skeleton_nodepath_not_allowed",
            })
            continue
        if ":" in decoded:
            conflicts.append({
                "mesh_path": owner_path,
                "raw_skeleton": raw,
                "decoded_skeleton": decoded,
                "reason": "skeleton_nodepath_subname_not_allowed",
            })
            continue
        resolved = resolve_decoded_nodepath(owner_path, decoded)
        if resolved is None:
            conflicts.append({
                "mesh_path": owner_path,
                "raw_skeleton": raw,
                "decoded_skeleton": decoded,
                "reason": "skeleton_nodepath_traverses_above_scene_root",
            })
            continue
        canonical = canonical_relative_nodepath(owner_path, resolved)
        canonical_literal = f"NodePath({json.dumps(canonical, ensure_ascii=False)})"
        if decoded != canonical or raw != canonical_literal:
            conflicts.append({
                "mesh_path": owner_path,
                "raw_skeleton": raw,
                "decoded_skeleton": decoded,
                "resolved_skeleton": resolved,
                "canonical_relative_skeleton": canonical,
                "canonical_literal": canonical_literal,
                "reason": "skeleton_nodepath_not_canonical_relative_encoding",
            })
    return conflicts


def _legacy_accepts_alias(scene_text: str) -> bool:
    evidence = skin.scene_integrity(scene_text)
    return bool(evidence and evidence[0].get("skinned_mesh_binding_present"))


def fixture(skeleton_value: str) -> str:
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
skeleton = {skeleton_value}
mesh = SubResource("Mesh_body")
skin = SubResource("Skin_body")
material_override = SubResource("Mat_body")
'''


def self_test() -> None:
    valid = fixture('NodePath("../Skeleton3D")')
    assert skeleton_nodepath_conflicts(valid) == []

    dot_alias = fixture('NodePath(".././Skeleton3D")')
    assert _legacy_accepts_alias(dot_alias), "regression precondition: authored-skin v3 accepts dot-segment skeleton alias"
    conflicts = skeleton_nodepath_conflicts(dot_alias)
    assert len(conflicts) == 1 and conflicts[0]["reason"] == "skeleton_nodepath_not_canonical_relative_encoding"

    detour_alias = fixture('NodePath("../../CharacterMount/Skeleton3D")')
    assert _legacy_accepts_alias(detour_alias), "regression precondition: authored-skin v3 accepts traversal detour skeleton alias"
    conflicts = skeleton_nodepath_conflicts(detour_alias)
    assert len(conflicts) == 1 and conflicts[0]["canonical_relative_skeleton"] == "../Skeleton3D"

    absolute_alias = fixture('NodePath("/NpcAgent/CharacterMount/Skeleton3D")')
    assert _legacy_accepts_alias(absolute_alias), "regression precondition: authored-skin v3 accepts absolute skeleton alias"
    conflicts = skeleton_nodepath_conflicts(absolute_alias)
    assert len(conflicts) == 1 and conflicts[0]["reason"] == "absolute_skeleton_nodepath_not_allowed"

    escaped_alias = fixture('NodePath("../\\u0053keleton3D")')
    conflicts = skeleton_nodepath_conflicts(escaped_alias)
    assert len(conflicts) == 1 and conflicts[0]["reason"] == "skeleton_nodepath_not_canonical_relative_encoding"

    subname = fixture('NodePath("../Skeleton3D:pose")')
    conflicts = skeleton_nodepath_conflicts(subname)
    assert len(conflicts) == 1 and conflicts[0]["reason"] == "skeleton_nodepath_subname_not_allowed"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_SKELETON_NODEPATH_CANONICALITY_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_skeleton_nodepath_canonicality.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    conflicts: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        conflicts.extend({"scene": rel, **item} for item in skeleton_nodepath_conflicts(scene_path.read_text(encoding="utf-8")))

    canonical = not conflicts
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_plus_decoded_canonical_relative_node_only_skeleton_nodepaths",
        "reachable_scene_count": len(scenes),
        "skeleton_nodepath_conflicts": conflicts,
        "skeleton_nodepaths_canonical": canonical,
        "dot_segment_skeleton_alias_evidence_accepted": False,
        "traversal_detour_skeleton_alias_evidence_accepted": False,
        "absolute_skeleton_nodepath_evidence_accepted": False,
        "escaped_noncanonical_skeleton_encoding_evidence_accepted": False,
        "skeleton_subname_evidence_accepted": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "canonicalize every MeshInstance3D skeleton NodePath before authored-skin evidence can be trusted" if not canonical else "retain canonical skeleton NodePath gate before loaded-scene Skin/bone approval",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
