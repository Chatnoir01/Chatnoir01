#!/usr/bin/env python3
from __future__ import annotations

import re
import tempfile
from pathlib import Path

import civ1_external_resource_backing as backing
import civ1_external_resource_backing_type_agreement as agreement

LEGACY_GD_RESOURCE_RE = re.compile(r'^\[gd_resource\s+type="([^"]+)"(?:\s+[^]]*)?\]$')


def legacy_tres_type(path: Path) -> str | None:
    with path.open("r", encoding="utf-8") as handle:
        for _ in range(12):
            line = handle.readline()
            if not line:
                break
            match = LEGACY_GD_RESOURCE_RE.fullmatch(line.strip())
            if match:
                return match.group(1)
    return None


def legacy_v2_backing_type(path: Path) -> tuple[str | None, str]:
    suffix = path.suffix.lower()
    if suffix == ".gd":
        return "Script", "gd_extension"
    if suffix == ".tscn":
        return "PackedScene", "tscn_extension"
    if suffix == ".tres":
        return legacy_tres_type(path), "tres_gd_resource_header"
    return None, "unsupported_extension"


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        assets = root / "assets"
        assets.mkdir()
        script = assets / "npc.gd"
        script.write_text("extends Node\n", encoding="utf-8")
        shader = assets / "npc.gdshader"
        shader.write_text("shader_type spatial;\n", encoding="utf-8")

        resources = {
            ("ExtResource", "Npc_script"): {
                "type": "Texture2D",
                "path": "res://assets/npc.gd",
                "id": "Npc_script",
            }
        }
        backed, path, digest, declared_type, lfs_pointer = backing.ext_resource_backed(
            resources, 'ExtResource("Npc_script")', root
        )
        assert backed is True, "causal precondition: existing backing proof accepts any nonempty materialized file"
        assert path == "res://assets/npc.gd"
        assert isinstance(digest, str) and digest.startswith("sha256:")
        assert declared_type == "Texture2D"
        assert lfs_pointer is False

        rows = [{
            "scene": "game/civ1.tscn",
            "line": 2,
            "path": path,
            "type": declared_type,
        }]
        conflicts, determined = agreement.backing_type_conflicts(rows, root)
        assert determined == 1
        assert conflicts[0]["deterministic_backing_type"] == "Script"

        assert legacy_v2_backing_type(shader) == (None, "unsupported_extension"), (
            "causal precondition: v2 left .gdshader backing type unverified"
        )
        shader_rows = [{
            "scene": "game/civ1.tscn",
            "line": 3,
            "path": "res://assets/npc.gdshader",
            "type": "Texture2D",
        }]
        shader_conflicts, shader_determined = agreement.backing_type_conflicts(shader_rows, root)
        assert shader_determined == 1
        assert shader_conflicts == [{
            "scene": "game/civ1.tscn",
            "line": 3,
            "path": "res://assets/npc.gdshader",
            "declared_type": "Texture2D",
            "deterministic_backing_type": "Shader",
            "determination_method": "gdshader_extension",
            "reason": "declared_type_disagrees_with_deterministic_backing_type",
        }]

        malformed_tres = assets / "malformed_skin.tres"
        malformed_tres.write_text(
            '[resource]\n[gd_resource type="Skin" format=3]\n',
            encoding="utf-8",
        )
        assert legacy_tres_type(malformed_tres) == "Skin", (
            "causal precondition: v1 scanned ahead and treated a late gd_resource header as deterministic"
        )
        assert agreement.deterministic_backing_type(
            root, "res://assets/malformed_skin.tres"
        ) == (None, "tres_header_not_first_nonempty_line")

    print("CIV1_EXTERNAL_RESOURCE_BACKING_TYPE_AGREEMENT_REGRESSION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
