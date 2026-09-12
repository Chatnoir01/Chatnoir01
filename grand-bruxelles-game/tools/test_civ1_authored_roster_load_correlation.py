#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "civ1_authored_roster_promotion_truth.py"
spec = importlib.util.spec_from_file_location("promotion_truth", MODULE_PATH)
assert spec and spec.loader
promotion_truth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(promotion_truth)

SCENE = '[gd_scene format=3]\n[ext_resource type="Script" path="res://game/scripts/humanoid_visual.gd" id="1_visual"]\n'
UNRELATED_LOAD = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    var civilian = "res://assets/characters/civilians/civ_a.glb"
    var police = "res://assets/characters/police/officer_a.glb"
    var unrelated = load("res://ui/icon.tscn")
    if unrelated is PackedScene:
        add_child(unrelated.instantiate())
'''

body = promotion_truth.strip_gdscript_comments(
    promotion_truth.function_body(UNRELATED_LOAD, "_build_profiled_npc")
)
assets = sorted(set(promotion_truth.NPC_ASSET_RE.findall(body)))

# Frozen v4 predicate: asset mentions, any load/exists, and any PackedScene/instantiate
# were independently sufficient, even when the load and instantiate were unrelated.
v4_load = bool(re.search(r'\b(?:ResourceLoader\.exists|load)\s*\(', body))
v4_instantiate = bool(re.search(r'\bPackedScene\b|\.instantiate\s*\(', body))
v4_authored_dispatch = bool(assets and v4_load and v4_instantiate)
assert len(assets) == 2
assert v4_authored_dispatch is True, "fixture must reproduce v4 unrelated-load false positive"

current = promotion_truth.analyze(SCENE, UNRELATED_LOAD)
assert current["asset_load_instantiation_correlation_required"] is True
assert current["authored_npc_asset_dispatch_statically_proven"] is False
assert current["authored_npc_asset_load_proven"] is False
assert current["authored_npc_scene_instantiation_proven"] is False
assert current["correlated_authored_loaded_variables"] == []
assert current["authored_civilian_police_roster_visual_ready"] is False
assert current["promotion_blocked"] is True
assert "npcagent_dispatch_has_no_correlated_authored_asset_load_and_instantiation_proof" in current["blocking_reasons"]

print("CIV1_AUTHORED_ROSTER_V4_UNRELATED_LOAD_FALSE_POSITIVE_REPRODUCED_AND_V5_REJECTED")
