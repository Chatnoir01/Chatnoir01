#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
witness = ROOT / "game" / "tests" / "anneessens_automatic_road_direct_spawn_witness_test.gd"
main_scene = ROOT / "game" / "main.tscn"
validator = ROOT / "game" / "tests" / "validate_anneessens_player_witness_evidence.py"
validator_regression = ROOT / "game" / "tests" / "test_validate_anneessens_player_witness_evidence.py"
workflow = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-anneessens-automatic-road-player-witness.yml"

assert witness.exists(), "missing Anneessens automatic-road player witness"
text = witness.read_text(encoding="utf-8")
for token in (
    'const MAIN_SCENE := preload("res://game/main.tscn")',
    "const ANNEESSENS_PLACE_ID := 1382734012",
    'const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"',
    'const RUNTIME_INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"',
    'const RUNTIME_INDEX_FORMAT := "grand-bruxelles-road-runtime-index-v1"',
    "const MIN_ROAD_AXIS_ALIGNMENT := 0.90",
    "resolver.apply_to_player(player, ANNEESSENS_PLACE_ID)",
    'automatic_road_direct_osm_id',
    'automatic_road_direct_source_path',
    'automatic_road_direct_source_sha256',
    'contains("Place Anneessens")',
    'automatic_road_direct_source_sightline_clear',
    'FileAccess.get_sha256(SOURCE_PATH).to_lower() != expected_source_sha',
    '_offset_matches_source_safe_candidate(offset_m)',
    'automatic_road_direct_ground_y',
    'automatic_road_direct_spawn_xz',
    'automatic_road_direct_target_xz',
    'automatic_road_direct_segment_index',
    'player body clearance no longer matches physics-backed ground',
    'player view is cross-road: alignment=',
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
    'func _trace_visual_blockers(camera: Camera3D) -> void:',
    'PhysicsRayQueryParameters3D.create(origin, origin + direction * 250.0)',
    'ANNEESSENS_VISUAL_BLOCKER_TRACE:',
    '_trace_visual_blockers(camera)',
    'camera_unchanged=true',
    'camera_clip_unchanged=true',
    'camera_cull_mask_unchanged=true',
    'source_sha=%s',
    'destination_advertisable=false',
    'jouable_authorized=false',
):
    assert token in text, f"missing fail-closed Anneessens witness token: {token}"

assert main_scene.exists(), "missing production main scene used by Anneessens witness"
main_scene_text = main_scene.read_text(encoding="utf-8")
assert 'path="res://game/scripts/osm_city_builder.gd"' in main_scene_text, "production main scene no longer wires the OSM city builder expected by the witness"
assert 'script = ExtResource("2_city")' in main_scene_text, "production BrusselsOSM node no longer uses the expected OSM city builder resource"

assert validator.exists(), "missing staged Anneessens evidence validator"
v = validator.read_text(encoding="utf-8")
for token in (
    'SCHEMA = "grand-bruxelles-anneessens-player-witness-v1"',
    'ROAD_OSM_ID = 1382734012',
    'FROZEN_FRAME_SIZE = (1280, 720)',
    'def png_dimensions(path: Path) -> tuple[int, int]:',
    'staged PNG dimensions are not frozen at 1280x720',
    'manifest frame dimensions do not match staged PNG bytes',
    '"frame_sha256"',
    '"runtime_log_sha256"',
    'manifest frame_sha256 does not match staged PNG bytes',
    'manifest runtime_log_sha256 does not match staged runtime log bytes',
    'visual_acceptance disagrees with frozen 3-ray/source-SHA rule',
    'evidence artifact may not self-advertise destination readiness',
    'evidence artifact may not self-authorize JOUABLE',
    'human review must remain required',
    'evidence-sha256.txt does not exactly bind staged evidence',
):
    assert token in v, f"missing staged evidence validator token: {token}"

assert validator_regression.exists(), "missing staged evidence tamper regression"
vr = validator_regression.read_text(encoding="utf-8")
for token in (
    'write_stage(stage, width=640, height=720)',
    'assert result.returncode == 1',
    'staged PNG dimensions are not frozen at 1280x720',
    'ANNEESSENS_PLAYER_WITNESS_EVIDENCE_VALIDATOR_REGRESSION_GREEN',
):
    assert token in vr, f"missing dimension-tamper regression token: {token}"

assert workflow.exists(), "missing dedicated Anneessens automatic-road player workflow"
w = workflow.read_text(encoding="utf-8")
for token in (
    "Godot_v4.7.1-stable_linux.x86_64",
    "grand-bruxelles-game/game/main.tscn",
    "grand-bruxelles-game/game/scripts/osm_city_builder.gd",
    "grand-bruxelles-game/game/scripts/brussels_osm_environment_runtime.gd",
    "anneessens_automatic_road_direct_spawn_witness_test.gd",
    "anneessens_automatic_road_player_witness_contract_test.py",
    "validate_anneessens_player_witness_evidence.py",
    "test_validate_anneessens_player_witness_evidence.py",
    "automatic-road-1382734012-player-witness",
    "runtime.log",
    "automatic_road_1382734012_player.png",
    "1280",
    "720",
    "evidence-manifest.json",
    '"road_osm_id": 1382734012',
    '"destination_advertisable": False',
    '"jouable_authorized": False',
    '"human_review_required": True',
    '"visual_acceptance": visual_acceptance',
    'visual_acceptance = len(traces) == 3 and 1 <= building_hits <= 2 and source_sha_matches',
    '"trace_count": len(traces)',
    '"building_hits": building_hits',
    '"source_sha256": computed_source_sha',
    '"emitted_source_sha256": emitted_source_sha',
    '"source_sha_matches": source_sha_matches',
    '"pr_head_sha": pr_head_sha',
    '"live_main_sha": live_main_sha',
    '"frame_sha256": frame_sha',
    '"runtime_log_sha256": runtime_log_sha',
    'Validate exact staged Anneessens evidence',
    'ANNEESSENS_VISUAL_REVIEW_REQUIRED',
    'if: always()',
    'if-no-files-found: error',
):
    assert token in w, f"missing workflow contract token: {token}"

for forbidden in (
    '"destination_advertisable": true',
    '"jouable_authorized": true',
    '"destination_advertisable": True',
    '"jouable_authorized": True',
    'test "$building_hits" -ge 1',
    'test "$building_hits" -le 2',
):
    assert forbidden not in w, f"Anneessens evidence workflow may not self-promote or turn human review into a technical gate: {forbidden}"

print("ANNEESSENS_AUTOMATIC_ROAD_PLAYER_WITNESS_CONTRACT_GREEN")
