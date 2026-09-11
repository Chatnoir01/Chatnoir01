#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import civ1_authored_skin_integrity as skin
import civ1_external_resource_identity_type_consistency as identity

SCHEMA = "grand-bruxelles-civ1-external-resource-backing-type-agreement-v3"
GD_RESOURCE_RE = re.compile(r'^\[gd_resource\s+type="([^"]+)"(?:\s+[^]]*)?\]$')


def deterministic_tres_type(path: Path) -> tuple[str | None, str]:
    try:
        with path.open("r", encoding="utf-8-sig") as handle:
            for _ in range(12):
                line = handle.readline()
                if not line:
                    break
                stripped = line.strip()
                if not stripped:
                    continue
                match = GD_RESOURCE_RE.fullmatch(stripped)
                if match:
                    return match.group(1), "tres_gd_resource_header"
                return None, "tres_header_not_first_nonempty_line"
    except (OSError, UnicodeDecodeError):
        pass
    return None, "tres_type_undetermined"


def deterministic_backing_type(project_root: Path, resource_path: str) -> tuple[str | None, str]:
    resolved = skin.res_to_file(project_root, resource_path)
    if resolved is None or not resolved.is_file():
        return None, "unresolved"
    suffix = resolved.suffix.lower()
    if suffix == ".gd":
        return "Script", "gd_extension"
    if suffix == ".gdshader":
        return "Shader", "gdshader_extension"
    if suffix == ".tscn":
        return "PackedScene", "tscn_extension"
    if suffix == ".tres":
        return deterministic_tres_type(resolved)
    return None, "unsupported_extension"


def backing_type_conflicts(declarations: list[dict[str, object]], project_root: Path) -> tuple[list[dict[str, object]], int]:
    conflicts: list[dict[str, object]] = []
    determined = 0
    for row in declarations:
        path = row.get("path")
        declared = row.get("type")
        if not isinstance(path, str) or not isinstance(declared, str):
            continue
        actual, method = deterministic_backing_type(project_root, path)
        if actual is None:
            continue
        determined += 1
        if actual != declared:
            conflicts.append({
                "scene": row.get("scene"),
                "line": row.get("line"),
                "path": path,
                "declared_type": declared,
                "deterministic_backing_type": actual,
                "determination_method": method,
                "reason": "declared_type_disagrees_with_deterministic_backing_type",
            })
    return conflicts, determined


def self_test() -> None:
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "assets").mkdir()
        script = root / "assets" / "npc.gd"
        script.write_text("extends Node\n", encoding="utf-8")
        shader = root / "assets" / "npc.gdshader"
        shader.write_text("shader_type spatial;\n", encoding="utf-8")
        scene = root / "assets" / "npc.tscn"
        scene.write_text("[gd_scene format=3]\n[node name=\"Npc\" type=\"Node3D\"]\n", encoding="utf-8")
        tres = root / "assets" / "npc_skin.tres"
        tres.write_text('[gd_resource type="Skin" format=3]\n\n[resource]\n', encoding="utf-8")
        tres_blank = root / "assets" / "npc_skin_blank.tres"
        tres_blank.write_text('\n\n[gd_resource type="Skin" format=3]\n\n[resource]\n', encoding="utf-8")
        tres_bom = root / "assets" / "npc_skin_bom.tres"
        tres_bom.write_text('\ufeff[gd_resource type="Skin" format=3]\n\n[resource]\n', encoding="utf-8")
        tres_late = root / "assets" / "npc_skin_late.tres"
        tres_late.write_text('[resource]\n[gd_resource type="Skin" format=3]\n', encoding="utf-8")

        assert deterministic_backing_type(root, "res://assets/npc.gd") == ("Script", "gd_extension")
        assert deterministic_backing_type(root, "res://assets/npc.gdshader") == ("Shader", "gdshader_extension")
        assert deterministic_backing_type(root, "res://assets/npc.tscn") == ("PackedScene", "tscn_extension")
        assert deterministic_backing_type(root, "res://assets/npc_skin.tres") == ("Skin", "tres_gd_resource_header")
        assert deterministic_backing_type(root, "res://assets/npc_skin_blank.tres") == ("Skin", "tres_gd_resource_header")
        assert deterministic_backing_type(root, "res://assets/npc_skin_bom.tres") == ("Skin", "tres_gd_resource_header")
        assert deterministic_backing_type(root, "res://assets/npc_skin_late.tres") == (None, "tres_header_not_first_nonempty_line")

        rows = [
            {"scene": "game/civ1.tscn", "line": 2, "path": "res://assets/npc.gd", "type": "Texture2D"},
            {"scene": "game/civ1.tscn", "line": 3, "path": "res://assets/npc.gdshader", "type": "Texture2D"},
            {"scene": "game/civ1.tscn", "line": 4, "path": "res://assets/npc.tscn", "type": "PackedScene"},
            {"scene": "game/civ1.tscn", "line": 5, "path": "res://assets/npc_skin.tres", "type": "Skin"},
        ]
        conflicts, determined = backing_type_conflicts(rows, root)
        assert determined == 4
        assert len(conflicts) == 2
        assert conflicts[0]["path"] == "res://assets/npc.gd"
        assert conflicts[0]["deterministic_backing_type"] == "Script"
        assert conflicts[1]["path"] == "res://assets/npc.gdshader"
        assert conflicts[1]["deterministic_backing_type"] == "Shader"


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_EXTERNAL_RESOURCE_BACKING_TYPE_AGREEMENT_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 3:
        print("usage: civ1_external_resource_backing_type_agreement.py MAIN_TSCN OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1]).resolve()
    out_path = Path(sys.argv[2])
    project_root = main_tscn.parent.parent
    scenes = skin.reachable_scenes(main_tscn, project_root)
    declarations: list[dict[str, object]] = []
    for scene_path in scenes:
        rel = scene_path.relative_to(project_root).as_posix()
        declarations.extend(identity.external_resource_declarations(scene_path.read_text(encoding="utf-8"), rel))

    conflicts, determined = backing_type_conflicts(declarations, project_root)
    result = {
        "schema": SCHEMA,
        "evidence_mode": "reachable_tscn_external_resource_declared_type_vs_deterministic_backing_type_for_gd_gdshader_tscn_and_header_position_validated_tres",
        "reachable_scene_count": len(scenes),
        "external_resource_declaration_count": len(declarations),
        "deterministically_typed_backing_count": determined,
        "external_resource_backing_type_conflicts": conflicts,
        "external_resource_declared_types_agree_with_deterministic_backing": not conflicts,
        "mismatched_script_type_evidence_accepted": False,
        "mismatched_shader_type_evidence_accepted": False,
        "late_tres_header_evidence_treated_as_deterministic": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": "retain deterministic backing/type agreement before authored Character loaded-scene approval" if not conflicts else "correct external resource declared type or backing resource before Character provenance can be trusted",
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0 if not conflicts else 1


if __name__ == "__main__":
    raise SystemExit(main())
