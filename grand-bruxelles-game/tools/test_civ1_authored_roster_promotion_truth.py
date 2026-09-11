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

# Frozen historical regexes: regressions must reproduce the old predicate, not
# silently inherit whatever hardened regex the current module exposes.
LEGACY_PLAYER_ASSET_RE = re.compile(r'res://assets/characters/player(?:/|_)[^"\']*', re.I)
LEGACY_NPC_ASSET_RE = re.compile(
    r'res://assets/characters/(?!player(?:/|_))[^"\']+\.(?:glb|gltf|fbx|tscn)', re.I
)

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
    LEGACY_PLAYER_ASSET_RE.findall(npc_body)
    or promotion_truth.re.search(r'\b_try_build_authored_character\s*\(', npc_body)
)
v1_authored_ready = bool(bound and npc_dispatch and not procedural_hits and not player_reuse)
assert v1_authored_ready is True, "fixture must reproduce the v1 false positive"

current = promotion_truth.analyze(SCENE, PLACEHOLDER)
assert current["authored_npc_asset_dispatch_statically_proven"] is False
assert current["multiple_authored_npc_identities_statically_proven"] is False
assert current["authored_civilian_police_roster_visual_ready"] is False
assert current["promotion_blocked"] is True

COMMENT_ONLY = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    # "res://assets/characters/civilians/civ_a.glb"
    # "res://assets/characters/police/officer_a.glb"
    var unrelated = load("res://ui/icon.tscn")
    if unrelated is PackedScene:
        add_child(unrelated.instantiate())
'''

# Reproduce v2 exactly. Quoted commented paths are important: the historical
# regex stopped at quotes, so this fixture proves two distinct fake identities.
comment_ready_body = promotion_truth.function_body(COMMENT_ONLY, "_ready")
comment_npc_body = promotion_truth.function_body(COMMENT_ONLY, "_build_profiled_npc")
v2_bound = promotion_truth.main_binds_humanoid_visual(SCENE)
v2_dispatch = bool(
    promotion_truth.re.search(r'if\s+actor\s+is\s+NpcAgent\s*:', comment_ready_body)
    and promotion_truth.re.search(r'_build_profiled_npc\s*\(', comment_ready_body)
)
v2_procedural = bool(promotion_truth.PROCEDURAL_HELPER_RE.search(comment_npc_body))
v2_player_reuse = bool(
    LEGACY_PLAYER_ASSET_RE.findall(comment_npc_body)
    or promotion_truth.re.search(r'\b_try_build_authored_character\s*\(', comment_npc_body)
)
v2_npc_assets = sorted(set(LEGACY_NPC_ASSET_RE.findall(comment_npc_body)))
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

current_comment = promotion_truth.analyze(SCENE, COMMENT_ONLY)
assert current_comment["comment_text_excluded_from_static_evidence"] is True
assert current_comment["authored_npc_asset_paths"] == []
assert current_comment["authored_civilian_police_roster_visual_ready"] is False

UNQUOTED_PSEUDO_PATHS = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    var fake_a = res://assets/characters/civilians/civ_a.glb
    var marker_a = ""
    var fake_b = res://assets/characters/police/officer_a.glb
    var marker_b = ""
    var unrelated = load("res://ui/icon.tscn")
    if unrelated is PackedScene:
        add_child(unrelated.instantiate())
'''

# Reproduce v3's remaining false positive: comments were removed, but the old
# path regex still accepted unquoted pseudo-path tokens as asset evidence.
unquoted_body = promotion_truth.function_body(UNQUOTED_PSEUDO_PATHS, "_build_profiled_npc")
unquoted_code = promotion_truth.strip_gdscript_comments(unquoted_body)
v3_assets = sorted(set(LEGACY_NPC_ASSET_RE.findall(unquoted_code)))
v3_authored_dispatch = bool(
    v3_assets
    and promotion_truth.RESOURCE_LOAD_RE.search(unquoted_code)
    and promotion_truth.PACKED_SCENE_INSTANTIATE_RE.search(unquoted_code)
)
assert len(v3_assets) >= 2, "fixture must expose at least two legacy pseudo-path identities"
assert v3_authored_dispatch is True, "fixture must reproduce v3 unquoted-path false evidence"

current_unquoted = promotion_truth.analyze(SCENE, UNQUOTED_PSEUDO_PATHS)
assert current_unquoted["quoted_asset_path_evidence_required"] is True
assert current_unquoted["authored_npc_asset_paths"] == []
assert current_unquoted["authored_npc_asset_dispatch_statically_proven"] is False
assert current_unquoted["multiple_authored_npc_identities_statically_proven"] is False
assert current_unquoted["authored_civilian_police_roster_visual_ready"] is False
assert current_unquoted["promotion_blocked"] is True

print("CIV1_AUTHORED_ROSTER_V1_V2_V3_FALSE_POSITIVES_REPRODUCED_AND_V4_REJECTED")
