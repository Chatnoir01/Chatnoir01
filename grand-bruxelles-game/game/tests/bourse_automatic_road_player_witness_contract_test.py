#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
witness = ROOT / "game" / "tests" / "bourse_automatic_road_direct_spawn_witness_test.gd"
workflow = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-bourse-automatic-road-player-witness.yml"
representative_witness = ROOT / "game" / "tests" / "bourse_8512036_candidate_player_witness_test.gd"
representative_workflow = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-bourse-8512036-candidate-player-witness.yml"

assert witness.exists(), "missing Auguste Orts legacy automatic-road player witness"
text = witness.read_text(encoding="utf-8")
for token in (
    "const BOURSE_ORTS_ID := 411724192",
    "resolver.apply_to_player(player, BOURSE_ORTS_ID)",
    'contains("Auguste Orts")',
    'automatic_road_direct_source_sightline_clear',
    'automatic_road_direct_ground_y',
    'automatic_road_411724192_player.png',
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
    assert token in text, f"missing fail-closed Auguste Orts legacy witness token: {token}"

assert workflow.exists(), "missing Auguste Orts legacy automatic-road workflow"
w = workflow.read_text(encoding="utf-8")
for token in (
    "Grand Bruxelles Bourse Auguste Orts 411724192 Legacy Compatibility Witness",
    "Godot_v4.7.1-stable_linux.x86_64",
    "bourse_automatic_road_direct_spawn_witness_test.gd",
    "automatic-road-411724192-legacy-compatibility-witness",
    "'witness_role': 'legacy_compatibility_only'",
    "'representative_destination': False",
    "'representative_destination_osm_id': 8512036",
    "'legacy_compatibility_only': True",
    "1280",
    "720",
):
    assert token in w, f"missing legacy witness role contract token: {token}"

# The Auguste Orts artifact is retained only as a compatibility witness. It must
# never masquerade as the representative automatic destination for Bourse.
assert "name: Grand Bruxelles Bourse Automatic Road Player Witness" not in w, (
    "legacy road-411724192 workflow must not use the generic representative Bourse title"
)
assert "name: automatic-road-411724192-player-witness\n" not in w, (
    "legacy road-411724192 artifact name must carry its compatibility-only role"
)

# Representative Bourse player evidence is a separate, source-backed road-8512036
# witness. Keeping the two roles separate prevents a valid but unrelated Orts
# frame from satisfying the Saint-Gery destination review.
assert representative_witness.exists(), "missing representative Bourse road-8512036 player witness"
assert representative_workflow.exists(), "missing representative Bourse road-8512036 workflow"
rep = representative_witness.read_text(encoding="utf-8")
for token in (
    "const OSM_ID := 8512036",
    'contains("Saint-G")',
    "automatic_road_8512036_player.png",
    "human_full_frame_review_required=true",
    "destination_advertisable=false",
    "visual_acceptance=false",
    "jouable_authorized=false",
):
    assert token in rep, f"missing representative Bourse road-8512036 contract token: {token}"

# Any source-backed or authored Shared Environment dependency capable of changing
# the deterministic legacy frame must retrigger the compatibility witness.
for path in (
    'grand-bruxelles-game/game/main.tscn',
    'grand-bruxelles-game/game/scripts/osm_city_builder.gd',
    'grand-bruxelles-game/game/scripts/brussels_osm_environment_runtime.gd',
    'grand-bruxelles-game/game/scripts/brussels_street_tree_asset.gd',
    'grand-bruxelles-game/game/scripts/brussels_street_tree_material.gd',
    'grand-bruxelles-game/game/scripts/brussels_street_lamp_asset.gd',
    'grand-bruxelles-game/game/scripts/brussels_bollard_asset.gd',
):
    assert f'- "{path}"' in w, f"Auguste Orts compatibility witness must rerun when player-visible dependency changes: {path}"

print(
    "BOURSE_AUTOMATIC_ROAD_PLAYER_WITNESS_CONTRACT_GREEN "
    "legacy_osm_id=411724192 representative_osm_id=8512036 "
    "legacy_compatibility_only=true unrelated_frame_cannot_satisfy_representative_review=true"
)
