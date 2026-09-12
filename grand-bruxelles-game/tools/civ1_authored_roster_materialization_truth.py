#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

import civ1_authored_roster_promotion_truth as promotion

SCHEMA = "grand-bruxelles-civ1-authored-roster-materialization-truth-v5"
_NODE_HEADER_RE = re.compile(r"^\[node\s+(.+)\]$")


def res_path_to_file(project_root: Path, res_path: str) -> Path:
    if not res_path.startswith("res://"):
        raise ValueError(f"not a Godot res path: {res_path}")
    relative = Path(res_path.removeprefix("res://"))
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"unsafe Godot res path: {res_path}")
    return project_root / relative


def _read_godot_text_scene(backing: Path) -> str | None:
    try:
        text = backing.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeError):
        return None
    first = next((line.strip() for line in text.splitlines() if line.strip()), "")
    if not (first.startswith("[gd_scene") and first.endswith("]") and "format=" in first):
        return None
    return text


def _read_gltf_json(backing: Path) -> dict[str, object] | None:
    try:
        data = json.loads(backing.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    asset = data.get("asset")
    if not (isinstance(asset, dict) and str(asset.get("version", "")).startswith("2")):
        return None
    return data


def _read_glb_v2(backing: Path) -> dict[str, object] | None:
    try:
        data = backing.read_bytes()
    except OSError:
        return None
    if len(data) < 20 or data[:4] != b"glTF":
        return None
    version, declared_length = struct.unpack_from("<II", data, 4)
    if version != 2 or declared_length != len(data):
        return None
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A or json_length <= 0 or 20 + json_length > len(data):
        return None
    try:
        json_chunk = data[20 : 20 + json_length].decode("utf-8").rstrip(" \t\r\n\x00")
        root = json.loads(json_chunk)
    except (UnicodeError, json.JSONDecodeError):
        return None
    if not isinstance(root, dict):
        return None
    asset = root.get("asset")
    if not (isinstance(asset, dict) and str(asset.get("version", "")).startswith("2")):
        return None
    return root


def _gltf_has_instantiable_scene_payload(root: dict[str, object]) -> bool:
    nodes = root.get("nodes")
    scenes = root.get("scenes")
    if not isinstance(nodes, list) or not nodes or not isinstance(scenes, list) or not scenes:
        return False
    for scene in scenes:
        if not isinstance(scene, dict):
            continue
        roots = scene.get("nodes")
        if not isinstance(roots, list) or not roots:
            continue
        for index in roots:
            if (
                isinstance(index, int)
                and not isinstance(index, bool)
                and 0 <= index < len(nodes)
                and isinstance(nodes[index], dict)
            ):
                return True
    return False


def _tscn_has_exact_attribute(attrs: str, key: str) -> bool:
    return re.search(rf"(?:^|\s){re.escape(key)}\s*=", attrs) is not None


def _tscn_has_instantiable_node_payload(text: str) -> bool:
    for raw_line in text.splitlines():
        line = raw_line.strip()
        match = _NODE_HEADER_RE.match(line)
        if match is None:
            continue
        attrs = match.group(1)
        if not _tscn_has_exact_attribute(attrs, "name"):
            continue
        if _tscn_has_exact_attribute(attrs, "type") or _tscn_has_exact_attribute(attrs, "instance"):
            return True
    return False


def scene_backing_inspection(backing: Path) -> tuple[str | None, bool]:
    suffix = backing.suffix.lower()
    if suffix == ".tscn":
        text = _read_godot_text_scene(backing)
        if text is None:
            return None, False
        return "godot_text_scene", _tscn_has_instantiable_node_payload(text)
    if suffix == ".gltf":
        root = _read_gltf_json(backing)
        if root is None:
            return None, False
        return "gltf_2_json", _gltf_has_instantiable_scene_payload(root)
    if suffix == ".glb":
        root = _read_glb_v2(backing)
        if root is None:
            return None, False
        return "glb_2", _gltf_has_instantiable_scene_payload(root)
    return None, False


def scene_backing_format(backing: Path) -> str | None:
    return scene_backing_inspection(backing)[0]


def analyze(scene: str, visual: str, project_root: Path) -> dict[str, object]:
    base = promotion.analyze(scene, visual)
    correlated = list(base.get("correlated_authored_asset_paths", []))
    materialized: list[str] = []
    scene_valid: list[str] = []
    payload_valid: list[str] = []
    missing_or_empty: list[str] = []
    invalid_or_unsupported: list[str] = []
    invalid_or_empty_payload: list[str] = []
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
        fmt, has_payload = scene_backing_inspection(backing)
        if fmt is None:
            invalid_or_unsupported.append(res_path)
            continue
        scene_valid.append(res_path)
        backing_formats[res_path] = fmt
        if not has_payload:
            invalid_or_empty_payload.append(res_path)
            continue
        payload_valid.append(res_path)

    all_materialized = bool(correlated) and not missing_or_empty and len(materialized) == len(correlated)
    all_scene_valid = bool(correlated) and not invalid_or_unsupported and len(scene_valid) == len(correlated)
    all_payload_valid = bool(correlated) and not invalid_or_empty_payload and len(payload_valid) == len(correlated)
    multiple_valid = len(payload_valid) >= 2
    static_ready = bool(base.get("authored_civilian_police_roster_visual_ready"))
    ready = static_ready and all_materialized and all_scene_valid and all_payload_valid and multiple_valid

    blockers = list(base.get("blocking_reasons", []))
    if correlated and missing_or_empty:
        blockers.append("correlated_authored_npc_assets_missing_or_empty")
    if correlated and invalid_or_unsupported:
        blockers.append("correlated_authored_npc_assets_not_valid_scene_backings")
    if correlated and invalid_or_empty_payload:
        blockers.append("correlated_authored_npc_assets_lack_instantiable_scene_payload")
    if static_ready and not multiple_valid:
        blockers.append("multiple_scene_payload_authored_npc_identities_not_proven")

    return {
        "schema": SCHEMA,
        "promotion_truth_schema": base.get("schema"),
        "correlated_authored_asset_paths": correlated,
        "materialized_correlated_authored_asset_paths": sorted(materialized),
        "scene_valid_correlated_authored_asset_paths": sorted(scene_valid),
        "scene_payload_valid_correlated_authored_asset_paths": sorted(payload_valid),
        "scene_backing_formats": dict(sorted(backing_formats.items())),
        "missing_or_empty_correlated_authored_asset_paths": sorted(missing_or_empty),
        "invalid_or_unsupported_scene_backing_paths": sorted(invalid_or_unsupported),
        "invalid_or_empty_scene_payload_paths": sorted(invalid_or_empty_payload),
        "correlated_asset_backing_required": True,
        "scene_format_preflight_required": True,
        "scene_payload_preflight_required": True,
        "concrete_scene_root_node_required": True,
        "exact_tscn_node_attribute_tokens_required": True,
        "all_correlated_authored_asset_backings_materialized": all_materialized,
        "all_correlated_authored_asset_scene_backings_valid": all_scene_valid,
        "all_correlated_authored_asset_scene_payloads_instantiable": all_payload_valid,
        "multiple_scene_payload_authored_npc_identities_proven": multiple_valid,
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
