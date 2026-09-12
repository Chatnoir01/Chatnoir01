#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import struct
import tempfile
from pathlib import Path

from civ1_authored_roster_materialization_truth import analyze, _read_godot_text_scene, _tscn_has_instantiable_node_payload

SCENE = '[gd_scene format=3]\n[ext_resource type="Script" path="res://game/scripts/humanoid_visual.gd" id="1_visual"]\n'
VISUAL = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    var civilian = "res://assets/characters/civilians/civ_a.glb"
    var police = "res://assets/characters/police/officer_a.glb"
    var candidate = civilian if agent.role != 1 else police
    var resource = load(candidate)
    if resource is PackedScene:
        add_child(resource.instantiate())
'''


def historical_v1_materialized(path: Path) -> bool:
    return path.is_file() and path.stat().st_size > 0


def glb_fixture(root: dict[str, object]) -> bytes:
    payload = json.dumps(root, separators=(",", ":")).encode("utf-8")
    payload += b" " * ((4 - len(payload) % 4) % 4)
    total = 20 + len(payload)
    return b"glTF" + struct.pack("<II", 2, total) + struct.pack("<II", len(payload), 0x4E4F534A) + payload


def historical_v2_glb_format_valid(data: bytes) -> bool:
    if len(data) < 20 or data[:4] != b"glTF":
        return False
    version, declared_length = struct.unpack_from("<II", data, 4)
    if version != 2 or declared_length != len(data):
        return False
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A or json_length <= 0 or 20 + json_length > len(data):
        return False
    try:
        root = json.loads(data[20 : 20 + json_length].decode("utf-8").rstrip(" \t\r\n\x00"))
    except (UnicodeError, json.JSONDecodeError):
        return False
    asset = root.get("asset") if isinstance(root, dict) else None
    return isinstance(asset, dict) and str(asset.get("version", "")).startswith("2")


def historical_v3_scene_payload_valid(root: dict[str, object]) -> bool:
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
        if any(isinstance(index, int) and not isinstance(index, bool) and 0 <= index < len(nodes) for index in roots):
            return True
    return False


def historical_v4_tscn_payload_valid(text: str) -> bool:
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not (line.startswith("[node ") and line.endswith("]")):
            continue
        attrs = line[len("[node ") : -1]
        if "name=" not in attrs:
            continue
        if "type=" in attrs or "instance=" in attrs:
            return True
    return False


def historical_v5_gd_scene_header_valid(text: str) -> bool:
    first = next((line.strip() for line in text.splitlines() if line.strip()), "")
    return first.startswith("[gd_scene") and first.endswith("]") and "format=" in first


def historical_v6_gd_scene_header_valid(text: str) -> bool:
    first = next((line.strip() for line in text.splitlines() if line.strip()), "")
    match = re.match(r"^\[gd_scene(?:\s+(.+))?\]$", first)
    if match is None:
        return False
    attrs = match.group(1) or ""
    return re.search(r"(?:^|\s)format\s*=", attrs) is not None


def historical_v7_gltf_asset_version_valid(root: dict[str, object]) -> bool:
    asset = root.get("asset")
    return isinstance(asset, dict) and str(asset.get("version", "")).startswith("2")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)

        phantom = analyze(SCENE, VISUAL, root)
        assert phantom["static_authored_roster_ready"] is True
        assert phantom["authored_civilian_police_roster_materialization_ready"] is False
        assert phantom["missing_or_empty_correlated_authored_asset_paths"] == [
            "res://assets/characters/civilians/civ_a.glb",
            "res://assets/characters/police/officer_a.glb",
        ]
        assert "correlated_authored_npc_assets_missing_or_empty" in phantom["blocking_reasons"]

        civilian = root / "assets/characters/civilians/civ_a.glb"
        police = root / "assets/characters/police/officer_a.glb"
        civilian.parent.mkdir(parents=True, exist_ok=True)
        police.parent.mkdir(parents=True, exist_ok=True)

        civilian.write_bytes(b"glTF-civilian-fixture")
        police.write_bytes(b"glTF-police-fixture")
        assert historical_v1_materialized(civilian) is True
        assert historical_v1_materialized(police) is True
        malformed = analyze(SCENE, VISUAL, root)
        assert malformed["all_correlated_authored_asset_backings_materialized"] is True
        assert malformed["all_correlated_authored_asset_scene_backings_valid"] is False
        assert malformed["scene_valid_correlated_authored_asset_paths"] == []
        assert malformed["invalid_or_unsupported_scene_backing_paths"] == [
            "res://assets/characters/civilians/civ_a.glb",
            "res://assets/characters/police/officer_a.glb",
        ]
        assert malformed["authored_civilian_police_roster_materialization_ready"] is False
        assert "correlated_authored_npc_assets_not_valid_scene_backings" in malformed["blocking_reasons"]

        metadata_only = glb_fixture({"asset": {"version": "2.0"}})
        assert historical_v2_glb_format_valid(metadata_only) is True
        civilian.write_bytes(metadata_only)
        police.write_bytes(metadata_only)
        empty_payload = analyze(SCENE, VISUAL, root)
        assert empty_payload["all_correlated_authored_asset_scene_backings_valid"] is True
        assert empty_payload["all_correlated_authored_asset_scene_payloads_instantiable"] is False
        assert empty_payload["scene_payload_valid_correlated_authored_asset_paths"] == []

        null_root_json = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [None]}
        assert historical_v3_scene_payload_valid(null_root_json) is True
        null_root_glb = glb_fixture(null_root_json)
        civilian.write_bytes(null_root_glb)
        police.write_bytes(null_root_glb)
        null_root = analyze(SCENE, VISUAL, root)
        assert null_root["all_correlated_authored_asset_scene_backings_valid"] is True
        assert null_root["all_correlated_authored_asset_scene_payloads_instantiable"] is False

        spoofed_tscn = '[gd_scene format=3]\n[node owner_name="Civilian" script_type="Node3D"]\n'
        canonical_tscn = '[gd_scene format=3]\n[node name="Civilian" type="Node3D"]\n'
        instance_tscn = '[gd_scene format=3]\n[node name="Civilian" instance=ExtResource("1_actor")]\n'
        assert historical_v4_tscn_payload_valid(spoofed_tscn) is True
        assert _tscn_has_instantiable_node_payload(spoofed_tscn) is False
        assert _tscn_has_instantiable_node_payload(canonical_tscn) is True
        assert _tscn_has_instantiable_node_payload(instance_tscn) is True

        spoofed_header = '[gd_scene foo_format=3]\n[node name="Civilian" type="Node3D"]\n'
        canonical_header = '[gd_scene load_steps=2 format=3]\n[node name="Civilian" type="Node3D"]\n'
        spoofed_header_path = root / "spoofed_header.tscn"
        canonical_header_path = root / "canonical_header.tscn"
        spoofed_header_path.write_text(spoofed_header, encoding="utf-8")
        canonical_header_path.write_text(canonical_header, encoding="utf-8")
        assert historical_v5_gd_scene_header_valid(spoofed_header) is True
        assert _read_godot_text_scene(spoofed_header_path) is None
        assert _read_godot_text_scene(canonical_header_path) == canonical_header

        malformed_format_header = '[gd_scene format=garbage]\n[node name="Civilian" type="Node3D"]\n'
        zero_format_header = '[gd_scene format=0]\n[node name="Civilian" type="Node3D"]\n'
        malformed_format_path = root / "malformed_format.tscn"
        zero_format_path = root / "zero_format.tscn"
        malformed_format_path.write_text(malformed_format_header, encoding="utf-8")
        zero_format_path.write_text(zero_format_header, encoding="utf-8")
        assert historical_v6_gd_scene_header_valid(malformed_format_header) is True
        assert historical_v6_gd_scene_header_valid(zero_format_header) is True
        assert _read_godot_text_scene(malformed_format_path) is None
        assert _read_godot_text_scene(zero_format_path) is None
        assert _read_godot_text_scene(canonical_header_path) == canonical_header

        spoofed_version_root = {"asset": {"version": "2beta"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "CharacterRoot"}]}
        assert historical_v7_gltf_asset_version_valid(spoofed_version_root) is True
        spoofed_version_glb = glb_fixture(spoofed_version_root)
        civilian.write_bytes(spoofed_version_glb)
        police.write_bytes(spoofed_version_glb)
        spoofed_version = analyze(SCENE, VISUAL, root)
        assert spoofed_version["all_correlated_authored_asset_backings_materialized"] is True
        assert spoofed_version["all_correlated_authored_asset_scene_backings_valid"] is False
        assert spoofed_version["invalid_or_unsupported_scene_backing_paths"] == [
            "res://assets/characters/civilians/civ_a.glb",
            "res://assets/characters/police/officer_a.glb",
        ]

        contentful_glb = glb_fixture({"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "CharacterRoot"}]})
        civilian.write_bytes(contentful_glb)
        police.write_bytes(contentful_glb)
        materialized = analyze(SCENE, VISUAL, root)
        assert materialized["concrete_scene_root_node_required"] is True
        assert materialized["exact_tscn_node_attribute_tokens_required"] is True
        assert materialized["exact_tscn_scene_header_format_token_required"] is True
        assert materialized["positive_integer_tscn_scene_format_required"] is True
        assert materialized["exact_gltf_asset_version_required"] is True
        assert materialized["all_correlated_authored_asset_backings_materialized"] is True
        assert materialized["all_correlated_authored_asset_scene_backings_valid"] is True
        assert materialized["all_correlated_authored_asset_scene_payloads_instantiable"] is True
        assert materialized["multiple_scene_payload_authored_npc_identities_proven"] is True
        assert materialized["missing_or_empty_correlated_authored_asset_paths"] == []
        assert materialized["invalid_or_unsupported_scene_backing_paths"] == []
        assert materialized["invalid_or_empty_scene_payload_paths"] == []
        assert materialized["scene_backing_formats"] == {
            "res://assets/characters/civilians/civ_a.glb": "glb_2",
            "res://assets/characters/police/officer_a.glb": "glb_2",
        }
        assert materialized["scene_payload_valid_correlated_authored_asset_paths"] == [
            "res://assets/characters/civilians/civ_a.glb",
            "res://assets/characters/police/officer_a.glb",
        ]
        assert materialized["authored_civilian_police_roster_materialization_ready"] is True

    print("CIV1_AUTHORED_ROSTER_MATERIALIZATION_TRUTH_V8_GREEN")


if __name__ == "__main__":
    main()
