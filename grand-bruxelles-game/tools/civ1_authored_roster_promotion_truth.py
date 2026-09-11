#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-authored-roster-promotion-truth-v2"
HUMANOID_VISUAL_PATH = "res://game/scripts/humanoid_visual.gd"
EXT_RESOURCE_RE = re.compile(r'^\s*\[ext_resource\s+([^]]+)\]\s*$', re.M)
ATTR_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"')
FUNC_RE = re.compile(r'^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', re.M)
PROCEDURAL_HELPER_RE = re.compile(r'\b_(?:elliptic_frustum_part|custom_ellipsoid_part|custom_prism_part|build_humanoid)\s*\(')
PLAYER_ASSET_RE = re.compile(r'res://assets/characters/player(?:/|_)[^"\']*', re.I)
NPC_ASSET_RE = re.compile(
    r'res://assets/characters/(?!player(?:/|_))[^"\']+\.(?:glb|gltf|fbx|tscn)', re.I
)
RESOURCE_LOAD_RE = re.compile(r'\b(?:ResourceLoader\.exists|load)\s*\(')
PACKED_SCENE_INSTANTIATE_RE = re.compile(r'\bPackedScene\b|\.instantiate\s*\(')


def function_body(script: str, function_name: str) -> str:
    matches = list(FUNC_RE.finditer(script))
    for index, match in enumerate(matches):
        if match.group(1) != function_name:
            continue
        end = matches[index + 1].start() if index + 1 < len(matches) else len(script)
        return script[match.start():end]
    return ""


def main_binds_humanoid_visual(scene: str) -> bool:
    for match in EXT_RESOURCE_RE.finditer(scene):
        attrs = dict(ATTR_RE.findall(match.group(1)))
        if attrs.get("type") == "Script" and attrs.get("path") == HUMANOID_VISUAL_PATH:
            return True
    return False


def analyze(scene: str, visual: str) -> dict[str, object]:
    ready_body = function_body(visual, "_ready")
    npc_body = function_body(visual, "_build_profiled_npc")
    bound = main_binds_humanoid_visual(scene)
    npc_dispatch = bool(
        re.search(r'if\s+actor\s+is\s+NpcAgent\s*:', ready_body)
        and re.search(r'_build_profiled_npc\s*\(', ready_body)
    )
    procedural_hits = [
        line.strip() for line in npc_body.splitlines() if PROCEDURAL_HELPER_RE.search(line)
    ]
    player_asset_hits = PLAYER_ASSET_RE.findall(npc_body)
    authored_helper_reuse = bool(re.search(r'\b_try_build_authored_character\s*\(', npc_body))
    player_reuse = bool(player_asset_hits or authored_helper_reuse)

    npc_asset_hits = sorted(set(NPC_ASSET_RE.findall(npc_body)))
    authored_resource_load = bool(RESOURCE_LOAD_RE.search(npc_body))
    authored_scene_instantiate = bool(PACKED_SCENE_INSTANTIATE_RE.search(npc_body))
    authored_asset_dispatch = bool(
        npc_asset_hits and authored_resource_load and authored_scene_instantiate
    )
    multiple_identities = len(npc_asset_hits) >= 2

    canonical_procedural = bool(bound and npc_dispatch and procedural_hits)
    authored_ready = bool(
        bound
        and npc_dispatch
        and not procedural_hits
        and not player_reuse
        and authored_asset_dispatch
        and multiple_identities
    )

    blockers: list[str] = []
    if not bound:
        blockers.append("canonical_main_does_not_bind_humanoid_visual")
    if not npc_dispatch:
        blockers.append("npcagent_dispatch_not_statically_proven")
    if procedural_hits:
        blockers.append("npcagent_dispatch_uses_procedural_profile_body")
    if player_reuse:
        blockers.append("npcagent_dispatch_reuses_player_authored_asset_path")
    if not authored_asset_dispatch:
        blockers.append("npcagent_dispatch_has_no_positive_authored_asset_load_proof")
    if not multiple_identities:
        blockers.append("multiple_authored_npc_identities_not_statically_proven")
    if not authored_ready and not blockers:
        blockers.append("authored_npc_visual_readiness_not_proven")

    return {
        "schema": SCHEMA,
        "canonical_humanoid_visual_bound": bound,
        "npcagent_dispatch_to_profiled_pipeline": npc_dispatch,
        "procedural_profile_fallback_detected": bool(procedural_hits),
        "procedural_profile_hits": procedural_hits,
        "canonical_npc_dispatch_is_procedural": canonical_procedural,
        "player_character_reuse_in_npc_dispatch_detected": player_reuse,
        "player_character_reuse_hits": player_asset_hits,
        "authored_npc_asset_paths": npc_asset_hits,
        "authored_npc_asset_load_proven": authored_resource_load,
        "authored_npc_scene_instantiation_proven": authored_scene_instantiate,
        "authored_npc_asset_dispatch_statically_proven": authored_asset_dispatch,
        "multiple_authored_npc_identities_statically_proven": multiple_identities,
        "authored_civilian_police_roster_visual_ready": authored_ready,
        "promotion_blocked": not authored_ready,
        "blocking_reasons": blockers,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": (
            "runtime owner #1591 must replace the canonical NpcAgent procedural profile dispatch with an authored, licensed, provenanced civilian/police roster before loaded-scene visual promotion"
            if canonical_procedural
            else "rerun Character/NPC loaded-scene readiness after positive authored NPC asset loading and multiple identities are statically proven"
        ),
    }


def self_test() -> None:
    scene = '[gd_scene format=3]\n[ext_resource type="Script" path="res://game/scripts/humanoid_visual.gd" id="1_visual"]\n'
    procedural = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
        return
func _build_profiled_npc(agent):
    _elliptic_frustum_part("Torso")
    _custom_ellipsoid_part("Head")
'''
    result = analyze(scene, procedural)
    assert result["canonical_npc_dispatch_is_procedural"] is True
    assert result["authored_civilian_police_roster_visual_ready"] is False
    assert result["promotion_blocked"] is True
    assert result["player_character_reuse_in_npc_dispatch_detected"] is False

    player_reuse = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    _try_build_authored_character()
'''
    result = analyze(scene, player_reuse)
    assert result["player_character_reuse_in_npc_dispatch_detected"] is True
    assert result["authored_civilian_police_roster_visual_ready"] is False

    placeholder_only = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    var character_mount = Node3D.new()
    character_mount.name = "CharacterMount"
    add_child(character_mount)
'''
    result = analyze(scene, placeholder_only)
    assert result["canonical_npc_dispatch_is_procedural"] is False
    assert result["authored_npc_asset_dispatch_statically_proven"] is False
    assert result["multiple_authored_npc_identities_statically_proven"] is False
    assert result["authored_civilian_police_roster_visual_ready"] is False
    assert result["promotion_blocked"] is True
    assert "npcagent_dispatch_has_no_positive_authored_asset_load_proof" in result["blocking_reasons"]

    single_authored = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    var candidate = "res://assets/characters/civilians/civ_a.glb"
    if ResourceLoader.exists(candidate):
        var resource = load(candidate)
        if resource is PackedScene:
            add_child(resource.instantiate())
'''
    result = analyze(scene, single_authored)
    assert result["authored_npc_asset_dispatch_statically_proven"] is True
    assert result["multiple_authored_npc_identities_statically_proven"] is False
    assert result["authored_civilian_police_roster_visual_ready"] is False

    authored_roster = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    var civilian = "res://assets/characters/civilians/civ_a.glb"
    var police = "res://assets/characters/police/officer_a.glb"
    var candidate = civilian if agent.role != 1 else police
    if ResourceLoader.exists(candidate):
        var resource = load(candidate)
        if resource is PackedScene:
            add_child(resource.instantiate())
'''
    result = analyze(scene, authored_roster)
    assert result["canonical_npc_dispatch_is_procedural"] is False
    assert result["player_character_reuse_in_npc_dispatch_detected"] is False
    assert result["authored_npc_asset_dispatch_statically_proven"] is True
    assert result["multiple_authored_npc_identities_statically_proven"] is True
    assert result["authored_civilian_police_roster_visual_ready"] is True
    assert result["promotion_blocked"] is False


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
        print("CIV1_AUTHORED_ROSTER_PROMOTION_TRUTH_SELF_TEST_OK")
        return 0
    if len(sys.argv) != 4:
        print("usage: civ1_authored_roster_promotion_truth.py MAIN_TSCN HUMANOID_VISUAL OUT", file=sys.stderr)
        return 2

    main_tscn = Path(sys.argv[1])
    humanoid_visual = Path(sys.argv[2])
    out = Path(sys.argv[3])
    result = analyze(
        main_tscn.read_text(encoding="utf-8"),
        humanoid_visual.read_text(encoding="utf-8"),
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
