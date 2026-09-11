#!/usr/bin/env python3
from __future__ import annotations

import json
import struct
import tempfile
from pathlib import Path

from civ1_authored_roster_materialization_truth import analyze

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

        # Historical v1 treated any non-empty file as a valid backing.
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

        # Causal v2 regression: a GLB 2.0 container with only asset metadata passed
        # the old format preflight even though it has no instantiable scene graph.
        metadata_only = glb_fixture({"asset": {"version": "2.0"}})
        assert historical_v2_glb_format_valid(metadata_only) is True
        civilian.write_bytes(metadata_only)
        police.write_bytes(metadata_only)
        empty_payload = analyze(SCENE, VISUAL, root)
        assert empty_payload["all_correlated_authored_asset_backings_materialized"] is True
        assert empty_payload["all_correlated_authored_asset_scene_backings_valid"] is True
        assert empty_payload["all_correlated_authored_asset_scene_payloads_instantiable"] is False
        assert empty_payload["scene_valid_correlated_authored_asset_paths"] == [
            "res://assets/characters/civilians/civ_a.glb",
            "res://assets/characters/police/officer_a.glb",
        ]
        assert empty_payload["scene_payload_valid_correlated_authored_asset_paths"] == []
        assert empty_payload["invalid_or_empty_scene_payload_paths"] == [
            "res://assets/characters/civilians/civ_a.glb",
            "res://assets/characters/police/officer_a.glb",
        ]
        assert empty_payload["authored_civilian_police_roster_materialization_ready"] is False
        assert "correlated_authored_npc_assets_lack_instantiable_scene_payload" in empty_payload["blocking_reasons"]

        # Positive control: both GLBs expose a real scene root referencing a real node.
        contentful_glb = glb_fixture(
            {
                "asset": {"version": "2.0"},
                "scene": 0,
                "scenes": [{"nodes": [0]}],
                "nodes": [{"name": "CharacterRoot"}],
            }
        )
        civilian.write_bytes(contentful_glb)
        police.write_bytes(contentful_glb)
        materialized = analyze(SCENE, VISUAL, root)
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

    print("CIV1_AUTHORED_ROSTER_MATERIALIZATION_TRUTH_V3_GREEN")


if __name__ == "__main__":
    main()
