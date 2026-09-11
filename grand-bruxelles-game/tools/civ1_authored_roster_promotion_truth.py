#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-authored-roster-promotion-truth-v5"
HUMANOID_VISUAL_PATH = "res://game/scripts/humanoid_visual.gd"
EXT_RESOURCE_RE = re.compile(r'^\s*\[ext_resource\s+([^]]+)\]\s*$', re.M)
ATTR_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"')
FUNC_RE = re.compile(r'^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', re.M)
PROCEDURAL_HELPER_RE = re.compile(r'\b_(?:elliptic_frustum_part|custom_ellipsoid_part|custom_prism_part|build_humanoid)\s*\(')
PLAYER_ASSET_RE = re.compile(r'(?<=["\'])res://assets/characters/player(?:/|_)[^"\'\r\n]*(?=["\'])', re.I)
NPC_ASSET_RE = re.compile(r'(?<=["\'])res://assets/characters/(?!player(?:/|_))[^"\'\r\n]+\.(?:glb|gltf|fbx|tscn)(?=["\'])', re.I)
NPC_LITERAL_ASSIGN_RE = re.compile(r'\b(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(["\'])(res://assets/characters/(?!player(?:/|_))[^"\'\r\n]+\.(?:glb|gltf|fbx|tscn))\2', re.I)
CHOICE_ASSIGN_RE = re.compile(r'\b(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s+if\b[^\r\n]*\belse\s+([A-Za-z_][A-Za-z0-9_]*)')
LOAD_ASSIGN_RE = re.compile(r'\b(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*load\s*\(\s*([A-Za-z_][A-Za-z0-9_]*|["\'][^"\'\r\n]+["\'])\s*\)')


def function_body(script: str, function_name: str) -> str:
    matches = list(FUNC_RE.finditer(script))
    for index, match in enumerate(matches):
        if match.group(1) != function_name:
            continue
        end = matches[index + 1].start() if index + 1 < len(matches) else len(script)
        return script[match.start():end]
    return ""


def strip_gdscript_comments(source: str) -> str:
    cleaned: list[str] = []
    for line in source.splitlines(keepends=True):
        quote: str | None = None
        escaped = False
        cut = len(line)
        for index, char in enumerate(line):
            if escaped:
                escaped = False
                continue
            if quote is not None:
                if char == "\\":
                    escaped = True
                elif char == quote:
                    quote = None
                continue
            if char in ('"', "'"):
                quote = char
                continue
            if char == "#":
                cut = index
                break
        prefix = line[:cut]
        if line.endswith("\n") and not prefix.endswith("\n"):
            prefix += "\n"
        cleaned.append(prefix)
    return "".join(cleaned)


def main_binds_humanoid_visual(scene: str) -> bool:
    for match in EXT_RESOURCE_RE.finditer(scene):
        attrs = dict(ATTR_RE.findall(match.group(1)))
        if attrs.get("type") == "Script" and attrs.get("path") == HUMANOID_VISUAL_PATH:
            return True
    return False


def correlated_authored_scene_flow(npc_code: str) -> tuple[bool, list[str]]:
    """Prove an NPC asset reaches load() and that exact loaded variable is instantiated.

    This is deliberately conservative static dataflow, not a GDScript parser. It supports
    direct NPC literals, variables assigned NPC literals, and one-line ternary selection
    between already-tainted variables. Unrelated load()/instantiate() calls cannot satisfy it.
    """
    tainted: set[str] = {m.group(1) for m in NPC_LITERAL_ASSIGN_RE.finditer(npc_code)}
    changed = True
    while changed:
        changed = False
        for m in CHOICE_ASSIGN_RE.finditer(npc_code):
            dst, left, right = m.groups()
            if left in tainted and right in tainted and dst not in tainted:
                tainted.add(dst)
                changed = True

    loaded_vars: list[str] = []
    for m in LOAD_ASSIGN_RE.finditer(npc_code):
        loaded, source = m.groups()
        source_is_npc = source in tainted
        if source[:1] in ('"', "'"):
            literal = source[1:-1]
            source_is_npc = bool(re.fullmatch(r'res://assets/characters/(?!player(?:/|_))[^"\'\r\n]+\.(?:glb|gltf|fbx|tscn)', literal, re.I))
        if not source_is_npc:
            continue
        if re.search(rf'\b{re.escape(loaded)}\s*\.\s*instantiate\s*\(', npc_code):
            loaded_vars.append(loaded)
    return bool(loaded_vars), sorted(set(loaded_vars))


def analyze(scene: str, visual: str) -> dict[str, object]:
    ready_body = function_body(visual, "_ready")
    npc_body = function_body(visual, "_build_profiled_npc")
    npc_code = strip_gdscript_comments(npc_body)
    bound = main_binds_humanoid_visual(scene)
    npc_dispatch = bool(re.search(r'if\s+actor\s+is\s+NpcAgent\s*:', ready_body) and re.search(r'_build_profiled_npc\s*\(', ready_body))
    procedural_hits = [line.strip() for line in npc_code.splitlines() if PROCEDURAL_HELPER_RE.search(line)]
    player_asset_hits = PLAYER_ASSET_RE.findall(npc_code)
    authored_helper_reuse = bool(re.search(r'\b_try_build_authored_character\s*\(', npc_code))
    player_reuse = bool(player_asset_hits or authored_helper_reuse)

    npc_asset_hits = sorted(set(NPC_ASSET_RE.findall(npc_code)))
    correlated_flow, loaded_vars = correlated_authored_scene_flow(npc_code)
    authored_resource_load = correlated_flow
    authored_scene_instantiate = correlated_flow
    authored_asset_dispatch = bool(npc_asset_hits and correlated_flow)
    multiple_identities = len(npc_asset_hits) >= 2

    canonical_procedural = bool(bound and npc_dispatch and procedural_hits)
    authored_ready = bool(bound and npc_dispatch and not procedural_hits and not player_reuse and authored_asset_dispatch and multiple_identities)

    blockers: list[str] = []
    if not bound: blockers.append("canonical_main_does_not_bind_humanoid_visual")
    if not npc_dispatch: blockers.append("npcagent_dispatch_not_statically_proven")
    if procedural_hits: blockers.append("npcagent_dispatch_uses_procedural_profile_body")
    if player_reuse: blockers.append("npcagent_dispatch_reuses_player_authored_asset_path")
    if not authored_asset_dispatch: blockers.append("npcagent_dispatch_has_no_correlated_authored_asset_load_and_instantiation_proof")
    if not multiple_identities: blockers.append("multiple_authored_npc_identities_not_statically_proven")
    if not authored_ready and not blockers: blockers.append("authored_npc_visual_readiness_not_proven")

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
        "correlated_authored_loaded_variables": loaded_vars,
        "asset_load_instantiation_correlation_required": True,
        "multiple_authored_npc_identities_statically_proven": multiple_identities,
        "comment_text_excluded_from_static_evidence": True,
        "quoted_asset_path_evidence_required": True,
        "authored_civilian_police_roster_visual_ready": authored_ready,
        "promotion_blocked": not authored_ready,
        "blocking_reasons": blockers,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "contact_verified": False,
        "foot_slide_verified": False,
        "next_action": ("runtime owner #1591 must replace the canonical NpcAgent procedural profile dispatch with an authored, licensed, provenanced civilian/police roster before loaded-scene visual promotion" if canonical_procedural else "rerun Character/NPC loaded-scene readiness after correlated authored NPC asset loading/instantiation and multiple identities are statically proven"),
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
    assert result["authored_npc_asset_dispatch_statically_proven"] is False
    assert result["authored_civilian_police_roster_visual_ready"] is False

    comment_only_roster = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    # candidate: "res://assets/characters/civilians/civ_a.glb"
    # candidate: "res://assets/characters/police/officer_a.glb"
    var unrelated = load("res://ui/icon.tscn")
    if unrelated is PackedScene:
        add_child(unrelated.instantiate())
'''
    result = analyze(scene, comment_only_roster)
    assert result["authored_npc_asset_paths"] == []
    assert result["authored_civilian_police_roster_visual_ready"] is False

    unquoted_pseudo_paths = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    var fake_a = res://assets/characters/civilians/civ_a.glb
    var fake_b = res://assets/characters/police/officer_a.glb
    var unrelated = load("res://ui/icon.tscn")
    add_child(unrelated.instantiate())
'''
    result = analyze(scene, unquoted_pseudo_paths)
    assert result["authored_npc_asset_paths"] == []
    assert result["authored_npc_asset_dispatch_statically_proven"] is False

    hash_in_string = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    var civilian = "res://assets/characters/civilians/civ#one.glb"
    var police = "res://assets/characters/police/officer#one.glb"
    var candidate = civilian if agent.role != 1 else police
    var resource = load(candidate)
    if resource is PackedScene:
        add_child(resource.instantiate())
'''
    result = analyze(scene, hash_in_string)
    assert len(result["authored_npc_asset_paths"]) == 2
    assert result["authored_civilian_police_roster_visual_ready"] is True

    unrelated_load = '''extends Node3D
func _ready():
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
func _build_profiled_npc(agent):
    var civilian = "res://assets/characters/civilians/civ_a.glb"
    var police = "res://assets/characters/police/officer_a.glb"
    var unrelated = load("res://ui/icon.tscn")
    add_child(unrelated.instantiate())
'''
    result = analyze(scene, unrelated_load)
    assert len(result["authored_npc_asset_paths"]) == 2
    assert result["authored_npc_asset_dispatch_statically_proven"] is False
    assert result["authored_civilian_police_roster_visual_ready"] is False

    authored_roster = '''extends Node3D
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
    result = analyze(scene, authored_roster)
    assert result["authored_npc_asset_dispatch_statically_proven"] is True
    assert result["multiple_authored_npc_identities_statically_proven"] is True
    assert result["authored_civilian_police_roster_visual_ready"] is True
    assert result["asset_load_instantiation_correlation_required"] is True


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test(); print("CIV1_AUTHORED_ROSTER_PROMOTION_TRUTH_SELF_TEST_OK"); return 0
    if len(sys.argv) != 4:
        print("usage: civ1_authored_roster_promotion_truth.py MAIN_TSCN HUMANOID_VISUAL OUT", file=sys.stderr); return 2
    result = analyze(Path(sys.argv[1]).read_text(encoding="utf-8"), Path(sys.argv[2]).read_text(encoding="utf-8"))
    out = Path(sys.argv[3]); out.parent.mkdir(parents=True, exist_ok=True); out.write_text(json.dumps(result, indent=2, sort_keys=True)+"\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True)); return 0

if __name__ == "__main__": raise SystemExit(main())
