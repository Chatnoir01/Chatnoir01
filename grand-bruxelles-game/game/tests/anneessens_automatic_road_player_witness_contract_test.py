#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
witness = ROOT / "game" / "tests" / "anneessens_automatic_road_direct_spawn_witness_test.gd"
workflow = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-anneessens-automatic-road-player-witness.yml"

assert witness.exists(), "missing Anneessens automatic-road player witness"
text = witness.read_text(encoding="utf-8")
for token in (
    "const ANNEESSENS_PLACE_ID := 1382734012",
    "resolver.apply_to_player(player, ANNEESSENS_PLACE_ID)",
    'contains("Place Anneessens")',
    'automatic_road_direct_source_sightline_clear',
    'automatic_road_direct_ground_y',
    'automatic_road_1382734012_player.png',
    "var camera_local_before := camera.transform",
    "var camera_fov_before := camera.fov",
    "var camera_projection_before := camera.projection",
    "var camera_near_before := camera.near",
    "var camera_far_before := camera.far",
    "var camera_cull_mask_before := camera.cull_mask",
    "var spring_local_before := spring_arm.transform",
    "var spring_length_before := spring_arm.spring_length",
    'automatic road resolver mutated production camera local transform',
    'automatic road resolver mutated production camera FOV',
    'automatic road resolver mutated production camera projection',
    'automatic road resolver mutated production camera near clip',
    'automatic road resolver mutated production camera far clip',
    'automatic road resolver mutated production camera cull mask',
    'automatic road resolver mutated production spring-arm transform',
    'automatic road resolver mutated production spring-arm length',
    'camera_unchanged=true',
    'camera_clip_unchanged=true',
    'camera_cull_mask_unchanged=true',
    'destination_advertisable=false',
    'jouable_authorized=false',
):
    assert token in text, f"missing fail-closed Anneessens witness token: {token}"

assert workflow.exists(), "missing dedicated Anneessens automatic-road player workflow"
w = workflow.read_text(encoding="utf-8")
for token in (
    "Godot_v4.7.1-stable_linux.x86_64",
    "anneessens_automatic_road_direct_spawn_witness_test.gd",
    "automatic-road-1382734012-player-witness",
    "1280",
    "720",
):
    assert token in w, f"missing workflow contract token: {token}"

print("ANNEESSENS_AUTOMATIC_ROAD_PLAYER_WITNESS_CONTRACT_GREEN")
