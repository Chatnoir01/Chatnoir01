#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

GATE = Path("grand-bruxelles-game/data/qa/automatic_road_player_visual_gate.json")
ROAD_TEST = Path("grand-bruxelles-game/game/tests/automatic_road_direct_spawn_test.gd")
ROAD_WORKFLOW = Path(".github/workflows/grand-bruxelles-automatic-road-spawn.yml")
PLAYER_WITNESS_TEST = Path("grand-bruxelles-game/game/tests/automatic_road_direct_spawn_witness_test.gd")
PLAYER_WITNESS_WORKFLOW = Path(".github/workflows/grand-bruxelles-automatic-road-player-witness.yml")

EXPECTED_ARTIFACT_SHA = "56d958a077a5bcbbfbf75b1344dfc12fe0f25300f38db2a144a6dea545a288f7"
EXPECTED_PNG_SHA = "5c0215788ac0dd77f8d07c69b0885a8f929e64e35bbd7c12a35fd439b5f74c87"
EXPECTED_DIAGNOSTIC_SHA = "223e3dc8063941f944010703bee519418f9a32c969735affd8f2d49956f5cacf"
EXPECTED_RUNTIME_LOG_SHA = "44fec3ba0108456d178fe9bc7d3e5720e77a4daea5b615d55da2ba9bffc44aa9"
EXPECTED_HEAD = "7fc8f2835b60cf6bc227a226c09bf5571e1ecfe6"
EXPECTED_BASE = "b96a21367f61830748bb9ba86c34cb71103fbcc3"
EXPECTED_RUN = 32830200285
EXPECTED_ARTIFACT = 9556476477
EXPECTED_ROAD = 359177328


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"AUTOMATIC_ROAD_PLAYER_VISUAL_GATE_FAIL: {message}")


def main() -> None:
    data = json.loads(GATE.read_text(encoding="utf-8"))
    require(data.get("schema") == "grand-bruxelles-automatic-road-player-visual-gate-v1", "schema drifted")

    evidence = data.get("evidence", {})
    require(evidence.get("production_base_sha") == EXPECTED_BASE, "evidence base drifted")
    require(evidence.get("evidence_head_sha") == EXPECTED_HEAD, "evidence head drifted")
    require(evidence.get("workflow_run_id") == EXPECTED_RUN, "workflow run drifted")
    require(evidence.get("artifact_id") == EXPECTED_ARTIFACT, "artifact id drifted")
    require(evidence.get("artifact_sha256") == EXPECTED_ARTIFACT_SHA, "artifact digest drifted")
    require(evidence.get("png_sha256") == EXPECTED_PNG_SHA, "PNG digest drifted")
    require(evidence.get("diagnostic_sha256") == EXPECTED_DIAGNOSTIC_SHA, "diagnostic digest drifted")
    require(evidence.get("runtime_log_sha256") == EXPECTED_RUNTIME_LOG_SHA, "runtime log digest drifted")
    require(evidence.get("resolution") == [1280, 720], "full-frame resolution drifted")
    require(evidence.get("witness_road_osm_id") == EXPECTED_ROAD, "Lemonnier witness identity drifted")
    require("Maurice Lemonnier" in str(evidence.get("witness_road_name", "")), "Lemonnier road name drifted")

    diagnostic = data.get("runtime_animation_diagnostic", {})
    require(diagnostic.get("production_base_sha") == EXPECTED_BASE, "runtime diagnostic base drifted")
    require(diagnostic.get("diagnostic_head_sha") == EXPECTED_HEAD, "runtime diagnostic head drifted")
    require(diagnostic.get("workflow_run_id") == EXPECTED_RUN and diagnostic.get("artifact_id") == EXPECTED_ARTIFACT, "runtime diagnostic evidence identity drifted")
    require(diagnostic.get("artifact_sha256") == EXPECTED_ARTIFACT_SHA, "runtime diagnostic artifact digest drifted")
    require(diagnostic.get("diagnostic_sha256") == EXPECTED_DIAGNOSTIC_SHA, "runtime diagnostic JSON digest drifted")
    require(diagnostic.get("runtime_log_sha256") == EXPECTED_RUNTIME_LOG_SHA, "runtime diagnostic log digest drifted")
    require(diagnostic.get("road_osm_id") == EXPECTED_ROAD, "runtime diagnostic road drifted")
    require(diagnostic.get("using_authored_character") is True and diagnostic.get("authored_character_found") is True, "authored player missing")
    require(diagnostic.get("animation_player_count") == 1 and diagnostic.get("animation_tree_count") == 0, "animation driver inventory drifted")
    require(diagnostic.get("authored_animation_count") == 76, "authored animation catalog size drifted")
    require(diagnostic.get("active_driver_count") == 1, "production authored driver must be active")
    require(diagnostic.get("active_driver") == "AnimationPlayer", "active driver type drifted")
    require(diagnostic.get("active_animation") == "Idle", "accepted witness must remain bound to authored Idle")
    require(diagnostic.get("current_animation") == "Idle" and diagnostic.get("assigned_animation") == "Idle", "AnimationPlayer playback identity drifted")
    require(diagnostic.get("is_playing") is True, "accepted witness AnimationPlayer is no longer playing")
    require(diagnostic.get("catalog_has_idle") is True and diagnostic.get("catalog_has_unarmed_idle") is True and diagnostic.get("catalog_has_t_pose") is True, "animation catalog proof drifted")
    require(diagnostic.get("status") == "candidate" and diagnostic.get("reason") == "active_authored_animation_driver", "runtime diagnostic state drifted")

    source = data.get("source_contract", {})
    require(source.get("lookup_mode") == "deterministic_runtime_index", "resolver provenance drifted")
    require(source.get("source_sha256") == "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398", "source SHA drifted")
    require(source.get("ground_collision_proven") is True and source.get("source_sightline_clear") is True, "ground/sightline proof lost")
    require(float(source.get("road_axis_alignment", 0.0)) >= 0.90, "road-axis player view alignment regressed")

    review = data.get("human_review", {})
    require(review.get("status") == "keep", "accepted non-T-pose frame was silently rejected")
    require(review.get("full_frame_inspected") is True and review.get("road_identity_matches_frame") is True, "full-frame/road review proof missing")
    require(review.get("blocking_reasons") == [], "accepted frame still carries blocking reasons")
    require("no longer in bind/T-pose" in str(review.get("notes", "")), "human review does not record resolved T-pose")

    auth = data.get("authorization", {})
    require(auth.get("qa_witness_accepted") is True, "accepted QA witness flag missing")
    for key in ("playability_claimed", "destination_advertisable", "jouable_authorized"):
        require(auth.get(key) is False, f"{key} must remain fail-closed despite accepted visual witness")

    road_test = ROAD_TEST.read_text(encoding="utf-8")
    require("AUTOMATIC_ROAD_RUNTIME_READY_GREEN:" in road_test, "route-ready marker missing")
    require("AUTOMATIC_ROAD_PLAYER_WITNESS_HOLD:" in road_test, "route-only gate must still refuse player publication authority")
    require("_authored_animation_driver_state" not in road_test, "route proof still inspects Character animation")

    workflow = ROAD_WORKFLOW.read_text(encoding="utf-8")
    require('grep -F "AUTOMATIC_ROAD_RUNTIME_READY_GREEN"' in workflow, "route workflow does not require route-ready proof")
    require('grep -F "animation_driver="' not in workflow, "route workflow still owns Character animation")

    witness_test = PLAYER_WITNESS_TEST.read_text(encoding="utf-8")
    for required in (
        '_authored_animation_driver_state', 'AnimationPlayer', 'AnimationTree', 'active_driver_count',
        'ANIMATION_DIAGNOSTIC_PATH', '_write_animation_diagnostic', 'animation_player_diagnostics',
        'root.get_node_or_null("AuthoredPlayerLocomotionRuntime")', 'bind_target', 'authored_locomotion_ready'
    ):
        require(required in witness_test, f"dedicated witness lost required production-binding proof: {required}")
    require("authored player animation driver inactive; refusing bind/T-pose player-view witness" in witness_test, "inactive-driver path no longer fails closed")

    witness_workflow = PLAYER_WITNESS_WORKFLOW.read_text(encoding="utf-8")
    require('grep -F "animation_driver="' in witness_workflow, "successful witness does not require animation provenance")
    require("automatic_road_359177328_player_animation_diagnostic.json" in witness_workflow, "animation diagnostic is not staged")
    require("evidence-sha256.txt" in witness_workflow and "sha256sum --check evidence-sha256.txt" in witness_workflow, "artifact hash self-verification lost")
    require("if-no-files-found: error" in witness_workflow, "artifact upload no longer fails closed")

    print("AUTOMATIC_ROAD_PLAYER_VISUAL_GATE_OK: review=KEEP road=359177328 animation_driver=AnimationPlayer animation=Idle t_pose=false qa_witness_accepted=true playability_claimed=false destination_advertisable=false jouable=false")


if __name__ == "__main__":
    main()
