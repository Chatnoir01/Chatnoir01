#!/usr/bin/env python3
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import civ1_authored_roster_promotion_truth as promotion

SCHEMA = "grand-bruxelles-civ1-authored-roster-materialization-truth-v2"


def res_path_to_file(project_root: Path, res_path: str) -> Path:
    if not res_path.startswith("res://"):
        raise ValueError(f"not a Godot res path: {res_path}")
    relative = Path(res_path.removeprefix("res://"))
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"unsafe Godot res path: {res_path}")
    return project_root / relative


def _valid_godot_text_scene(backing: Path) -> bool:
    try:
        text = backing.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeError):
        return False
    first = next((line.strip() for line in text.splitlines() if line.strip()), "")
    return first.startswith("[gd_scene") and first.endswith("]") and "format=" in first


def _valid_gltf_json(backing: Path) -> bool:
    try:
        data = json.loads(backing.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return False
    if not isinstance(data, dict):
        return False
    asset = data.get("asset")
    return isinstance(asset, dict) and str(asset.get("version", "")).startswith("2")


def _valid_glb_v2(backing: Path) -> bool:
    try:
        data = backing.read_bytes()
    except OSError:
        return False
    if len(data) < 20 or data[:4] != b"glTF":
        return False
    version, declared_length = struct.unpack_from("<II", data, 4)
    if version != 2 or declared_length != len(data):
        return False
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A or json_length <= 0 or 20 + json_length > len(data):
        return False
    try:
        json_chunk = data[20 : 20 + json_length].decode("utf-8").rstrip(" \t\r\n\x00")
        root = json.loads(json_chunk)
    except (UnicodeError, json.JSONDecodeError):
        return False
    asset = root.get("asset") if isinstance(root, dict) else None
    return isinstance(asset, dict) and str(asset.get("version", "")).startswith("2")


def scene_backing_format(backing: Path) -> str | None:
    suffix = backing.suffix.lower()
    if suffix == ".tscn" and _valid_godot_text_scene(backing):
        return "godot_text_scene"
    if suffix == ".gltf" and _valid_gltf_json(backing):
        return "gltf_2_json"
    if suffix == ".glb" and _valid_glb_v2(backing):
        return "glb_2"
    return None


def analyze(scene: str, visual: str, project_root: Path) -> dict[str, object]:
    base = promotion.analyze(scene, visual)
    correlated = list(base.get("correlated_authored_asset_paths", []))
    materialized: list[str] = []
    scene_valid: list[str] = []
    missing_or_empty: list[str] = []
    invalid_or_unsupported: list[str] = []
    backing_formats: dict[str, str] = {}

    for res_path in correlated:
        try:
            backing = res_path_to_file(project_root, res_path)
        except ValueError:
            invalid_or_unsupported.append(res_path)
            continue
        if not backing.is_file() or backing.stat().st_size <= 0:
            missing_or_empty.append(res_path)
            continue
        materialized.append(res_path)
        fmt = scene_backing_format(backing)
        if fmt is None:
            invalid_or_unsupported.append(res_path)
            continue
        scene_valid.append(res_path)
        backing_formats[res_path] = fmt

    all_materialized = bool(correlated) and not missing_or_empty and len(materialized) == len(correlated)
    all_scene_valid = bool(correlated) and not invalid_or_unsupported and len(scene_valid) == len(correlated)
    multiple_valid = len(scene_valid) >= 2
    static_ready = bool(base.get("authored_civilian_police_roster_visual_ready"))
    ready = static_ready and all_materialized and all_scene_valid and multiple_valid

    blockers = list(base.get("blocking_reasons", []))
    if correlated and missing_or_empty:
        blockers.append("correlated_authored_npc_assets_missing_or_empty")
    if correlated and invalid_or_unsupported:
        blockers.append("correlated_authored_npc_assets_not_valid_scene_backings")
    if static_ready and not multiple_valid:
        blockers.append("multiple_scene_valid_authored_npc_identities_not_proven")

    return {
        "schema": SCHEMA,
        "promotion_truth_schema": base.get("schema"),
        "correlated_authored_asset_paths": correlated,
        "materialized_correlated_authored_asset_paths": sorted(materialized),
        "scene_valid_correlated_authored_asset_paths": sorted(scene_valid),
        "scene_backing_formats": dict(sorted(backing_formats.items())),
        "missing_or_empty_correlated_authored_asset_paths": sorted(missing_or_empty),
        "invalid_or_unsupported_scene_backing_paths": sorted(invalid_or_unsupported),
        "correlated_asset_backing_required": True,
        "scene_format_preflight_required": True,
        "all_correlated_authored_asset_backings_materialized": all_materialized,
        "all_correlated_authored_asset_scene_backings_valid": all_scene_valid,
        "multiple_scene_valid_authored_npc_identities_proven": multiple_valid,
        "static_authored_roster_ready": static_ready,
        "authored_civilian_police_roster_materialization_ready": ready,
        "promotion_blocked": not ready,
        "blocking_reasons": blockers,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
    }


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: civ1_authored_roster_materialization_truth.py MAIN_TSCN HUMANOID_VISUAL PROJECT_ROOT OUT", file=sys.stderr)
        return 2
    scene_path = Path(sys.argv[1])
    visual_path = Path(sys.argv[2])
    project_root = Path(sys.argv[3])
    result = analyze(scene_path.read_text(encoding="utf-8"), visual_path.read_text(encoding="utf-8"), project_root)
    out = Path(sys.argv[4])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
