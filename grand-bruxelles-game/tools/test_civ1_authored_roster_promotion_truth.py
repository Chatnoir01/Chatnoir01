#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "civ1_authored_roster_promotion_truth.py"
spec = importlib.util.spec_from_file_location("promotion_truth", MODULE_PATH)
assert spec and spec.loader
promotion_truth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(promotion_truth)

SCENE = '[gd_scene format=3]\n[ext_resource type="Script" path="res://game/scripts/humanoid_visual.gd" id="1_visual"]\n'
PLACEHOLDER = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    var character_mount = Node3D.new()
    character_mount.name = "CharacterMount"
    add_child(character_mount)
'''

# Reproduce the v1 readiness predicate: bound + dispatch + no procedural helper + no player reuse.
ready_body = promotion_truth.function_body(PLACEHOLDER, "_ready")
npc_body = promotion_truth.function_body(PLACEHOLDER, "_build_profiled_npc")
bound = promotion_truth.main_binds_humanoid_visual(SCENE)
npc_dispatch = bool(
    promotion_truth.re.search(r'if\s+actor\s+is\s+NpcAgent\s*:', ready_body)
    and promotion_truth.re.search(r'_build_profiled_npc\s*\(', ready_body)
)
procedural_hits = [
    line.strip()
    for line in npc_body.splitlines()
    if promotion_truth.PROCEDURAL_HELPER_RE.search(line)
]
player_reuse = bool(
    promotion_truth.PLAYER_ASSET_RE.findall(npc_body)
    or promotion_truth.re.search(r'\b_try_build_authored_character\s*\(', npc_body)
)
v1_authored_ready = bool(bound and npc_dispatch and not procedural_hits and not player_reuse)
assert v1_authored_ready is True, "fixture must reproduce the v1 false positive"

v2 = promotion_truth.analyze(SCENE, PLACEHOLDER)
assert v2["authored_npc_asset_dispatch_statically_proven"] is False
assert v2["multiple_authored_npc_identities_statically_proven"] is False
assert v2["authored_civilian_police_roster_visual_ready"] is False
assert v2["promotion_blocked"] is True
assert "npcagent_dispatch_has_no_positive_authored_asset_load_proof" in v2["blocking_reasons"]
assert "multiple_authored_npc_identities_not_statically_proven" in v2["blocking_reasons"]

print("CIV1_AUTHORED_ROSTER_PLACEHOLDER_FALSE_POSITIVE_REPRODUCED_AND_REJECTED")
