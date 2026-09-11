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


def glb_v2_fixture() -> bytes:
    root = json.dumps({"asset": {"version": "2.0"}}, separators=(",", ":")).encode("utf-8")
    root += b" " * ((4 - len(root) % 4) % 4)
    total = 20 + len(root)
    return b"glTF" + struct.pack("<II", 2, total) + struct.pack("<II", len(root), 0x4E4F534A) + root


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

        # Causal regression: v1 treated any non-empty file as a valid backing.
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

        valid_glb = glb_v2_fixture()
        civilian.write_bytes(valid_glb)
        police.write_bytes(valid_glb)
        materialized = analyze(SCENE, VISUAL, root)
        assert materialized["all_correlated_authored_asset_backings_materialized"] is True
        assert materialized["all_correlated_authored_asset_scene_backings_valid"] is True
        assert materialized["multiple_scene_valid_authored_npc_identities_proven"] is True
        assert materialized["missing_or_empty_correlated_authored_asset_paths"] == []
        assert materialized["invalid_or_unsupported_scene_backing_paths"] == []
        assert materialized["scene_backing_formats"] == {
            "res://assets/characters/civilians/civ_a.glb": "glb_2",
            "res://assets/characters/police/officer_a.glb": "glb_2",
        }
        assert materialized["authored_civilian_police_roster_materialization_ready"] is True

    print("CIV1_AUTHORED_ROSTER_MATERIALIZATION_TRUTH_V2_GREEN")


if __name__ == "__main__":
    main()
