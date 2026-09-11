#!/usr/bin/env python3
from __future__ import annotations

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

        materialized = analyze(SCENE, VISUAL, root)
        assert materialized["all_correlated_authored_asset_backings_materialized"] is True
        assert materialized["multiple_materialized_authored_npc_identities_proven"] is True
        assert materialized["missing_or_empty_correlated_authored_asset_paths"] == []
        assert materialized["authored_civilian_police_roster_materialization_ready"] is True

    print("CIV1_AUTHORED_ROSTER_MATERIALIZATION_TRUTH_GREEN")


if __name__ == "__main__":
    main()
