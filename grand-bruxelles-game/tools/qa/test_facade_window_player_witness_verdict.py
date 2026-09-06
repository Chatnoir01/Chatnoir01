from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
VERDICT_PATH = ROOT / "grand-bruxelles-game/data/qa/facade_window_player_witness_verdict.json"
BUILDER_PATH = ROOT / "grand-bruxelles-game/game/scripts/osm_city_builder.gd"

EXPECTED_MAIN = "5ed1e30903c62860379713d2879b1fda002c1d23"
EXPECTED_SOURCE_SHA256 = "a96123a6098c2a94dcef2622b6ea099c831f426e1ebfeb28a2edda74675c2493"
EXPECTED_BUILDER_BLOB = "d7d9292998180c905684c22fc89a332ce6bdf39a"
EXPECTED_ARTIFACT_DIGEST = "sha256:e5520332d1a7ce28992f1204affd292428b3023ac4a898ef34c585d55cf9f29e"


def test_facade_window_negative_verdict_lock() -> None:
    verdict = json.loads(VERDICT_PATH.read_text(encoding="utf-8"))
    assert verdict["schema"] == "grand-bruxelles-facade-window-player-witness-verdict-v1"
    assert verdict["production_main_sha"] == EXPECTED_MAIN

    evidence = verdict["evidence"]
    assert evidence["head_sha"] == "4b8dd91875900d58c1bafea950a127c059e47b7f"
    assert evidence["workflow_run_id"] == 32673893611
    assert evidence["artifact_id"] == 9502126208
    assert evidence["artifact_digest"] == EXPECTED_ARTIFACT_DIGEST
    assert evidence["resolution"] == [1280, 720]
    assert evidence["camera_fov"] == 69.0
    assert evidence["target_road_osm_id"] == 359177328
    assert evidence["window_instance_count"] == 913
    assert evidence["control_changed_pixels"] == 0
    assert evidence["control_changed_fraction"] == 0.0
    assert evidence["control_bbox"] == []

    # This file is a durable historical rejection receipt. Lock the source and
    # implementation identities recorded by that receipt, not the mutable bytes
    # currently checked out. Requiring today's source/builder hashes would turn
    # unrelated source-backed corridor work into a false failure and, worse,
    # encourage weakening or deleting a still-valid negative human verdict.
    source = verdict["source"]
    assert source["sha256"] == EXPECTED_SOURCE_SHA256
    assert source["license"] == "ODbL-1.0"
    assert source["building_footprint_placement_source_backed"] is True
    for key in (
        "window_presence_source_backed",
        "window_dimensions_source_backed",
        "window_grid_source_backed",
        "window_material_identity_source_backed",
    ):
        assert source[key] is False

    implementation = verdict["implementation_lock"]
    assert implementation["osm_city_builder_git_blob"] == EXPECTED_BUILDER_BLOB
    assert implementation["facade_window_instance_cap"] == 2600

    # The current runtime must still expose the same facade-window subsystem
    # semantics before this historical rejection can guard it. If these markers
    # disappear or the cap changes, fail closed and require fresh player-view
    # evidence rather than silently carrying the old verdict onto a new system.
    builder = BUILDER_PATH.read_text(encoding="utf-8")
    assert 'window_instance.name = "CorridorFacadeWindows"' in builder
    assert "if _window_transforms.size() >= 2600:" in builder

    decision = verdict["verdict"]
    assert decision["machine"] == "REJECT_LOW_SCREEN_COVERAGE"
    assert decision["human_full_frame"] == "REJECT_LOW_SCREEN_COVERAGE"
    assert decision["art_pass_authorized"] is False
    assert decision["camera_rescue_authorized"] is False
    assert decision["threshold_relaxation_authorized"] is False
    assert decision["runtime_changed"] is False
    assert decision["geometry_changed"] is False
    assert decision["requires_new_player_view_evidence_to_reopen"] is True


if __name__ == "__main__":
    test_facade_window_negative_verdict_lock()
    print("BRUSSELS_FACADE_WINDOW_NEGATIVE_VERDICT_OK")
