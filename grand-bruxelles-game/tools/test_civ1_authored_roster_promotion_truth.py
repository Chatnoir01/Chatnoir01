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

v3 = promotion_truth.analyze(SCENE, PLACEHOLDER)
assert v3["authored_npc_asset_dispatch_statically_proven"] is False
assert v3["multiple_authored_npc_identities_statically_proven"] is False
assert v3["authored_civilian_police_roster_visual_ready"] is False
assert v3["promotion_blocked"] is True
assert "npcagent_dispatch_has_no_positive_authored_asset_load_proof" in v3["blocking_reasons"]
assert "multiple_authored_npc_identities_not_statically_proven" in v3["blocking_reasons"]

COMMENT_ONLY = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    # res://assets/characters/civilians/civ_a.glb
    # res://assets/characters/police/officer_a.glb
    var unrelated = load("res://ui/icon.tscn")
    if unrelated is PackedScene:
        add_child(unrelated.instantiate())
'''

# Reproduce the v2 false positive exactly: it scanned raw function text, so two
# commented NPC paths plus unrelated load/instantiate signals could satisfy readiness.
comment_ready_body = promotion_truth.function_body(COMMENT_ONLY, "_ready")
comment_npc_body = promotion_truth.function_body(COMMENT_ONLY, "_build_profiled_npc")
v2_bound = promotion_truth.main_binds_humanoid_visual(SCENE)
v2_dispatch = bool(
    promotion_truth.re.search(r'if\s+actor\s+is\s+NpcAgent\s*:', comment_ready_body)
    and promotion_truth.re.search(r'_build_profiled_npc\s*\(', comment_ready_body)
)
v2_procedural = bool(promotion_truth.PROCEDURAL_HELPER_RE.search(comment_npc_body))
v2_player_reuse = bool(
    promotion_truth.PLAYER_ASSET_RE.findall(comment_npc_body)
    or promotion_truth.re.search(r'\b_try_build_authored_character\s*\(', comment_npc_body)
)
v2_npc_assets = sorted(set(promotion_truth.NPC_ASSET_RE.findall(comment_npc_body)))
v2_load = bool(promotion_truth.RESOURCE_LOAD_RE.search(comment_npc_body))
v2_instantiate = bool(promotion_truth.PACKED_SCENE_INSTANTIATE_RE.search(comment_npc_body))
v2_authored_dispatch = bool(v2_npc_assets and v2_load and v2_instantiate)
v2_multiple = len(v2_npc_assets) >= 2
v2_authored_ready = bool(
    v2_bound
    and v2_dispatch
    and not v2_procedural
    and not v2_player_reuse
    and v2_authored_dispatch
    and v2_multiple
)
assert v2_authored_ready is True, "fixture must reproduce the v2 comment-only false positive"

v3_comment = promotion_truth.analyze(SCENE, COMMENT_ONLY)
assert v3_comment["comment_text_excluded_from_static_evidence"] is True
assert v3_comment["authored_npc_asset_paths"] == []
assert v3_comment["authored_npc_asset_dispatch_statically_proven"] is False
assert v3_comment["multiple_authored_npc_identities_statically_proven"] is False
assert v3_comment["authored_civilian_police_roster_visual_ready"] is False
assert v3_comment["promotion_blocked"] is True

print("CIV1_AUTHORED_ROSTER_V1_PLACEHOLDER_AND_V2_COMMENT_FALSE_POSITIVES_REPRODUCED_AND_REJECTED")
