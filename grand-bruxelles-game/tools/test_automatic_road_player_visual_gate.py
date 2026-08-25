#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

GATE = Path("grand-bruxelles-game/data/qa/automatic_road_player_visual_gate.json")
ROAD_TEST = Path("grand-bruxelles-game/game/tests/automatic_road_direct_spawn_test.gd")
ROAD_WORKFLOW = Path(".github/workflows/grand-bruxelles-automatic-road-spawn.yml")
PLAYER_WITNESS_TEST = Path("grand-bruxelles-game/game/tests/automatic_road_direct_spawn_witness_test.gd")
PLAYER_WITNESS_WORKFLOW = Path(".github/workflows/grand-bruxelles-automatic-road-player-witness.yml")
EXPECTED_ARTIFACT_SHA = "97a1a8b7fd6f14223d9bedc3751efb893c74ca1b55a55721ca0514c164bdb9f0"
EXPECTED_PNG_SHA = "fcf9ccb1cfb61ec18e869772906aa22e59de7c0e5a3b551cb5c237b0327aa67a"
EXPECTED_MANIFEST_SHA = "79f2b9a19f4ffe0a309b98a01687563e04370574ab4b069a7fec80ad26490efe"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"AUTOMATIC_ROAD_PLAYER_VISUAL_GATE_FAIL: {message}")


def main() -> None:
    data = json.loads(GATE.read_text(encoding="utf-8"))
    require(data.get("schema") == "grand-bruxelles-automatic-road-player-visual-gate-v1", "schema drifted")
    evidence = data.get("evidence", {})
    require(evidence.get("production_base_sha") == "7c0df3c930b47d7eadada57680ff62b30d7b35ec", "review base drifted")
    require(evidence.get("evidence_head_sha") == "eb3a7e4a83f6d982fd8085ad0db90b28e440a2d2", "review head drifted")
    require(evidence.get("workflow_run_id") == 32795145150, "workflow run drifted")
    require(evidence.get("artifact_id") == 9544576806, "artifact id drifted")
    require(evidence.get("artifact_sha256") == EXPECTED_ARTIFACT_SHA, "artifact digest drifted")
    require(evidence.get("png_sha256") == EXPECTED_PNG_SHA, "PNG digest drifted")
    require(evidence.get("manifest_sha256") == EXPECTED_MANIFEST_SHA, "manifest digest drifted")
    require(evidence.get("resolution") == [1280, 720], "full-frame resolution drifted")
    require(evidence.get("witness_road_osm_id") == 408211693, "visible Fonsny identity drifted")
    require(evidence.get("lemonnier_probe_osm_id") == 359177328, "Lemonnier probe identity drifted")

    source = data.get("source_contract", {})
    require(source.get("lookup_mode") == "deterministic_runtime_index", "resolver provenance drifted")
    require(source.get("ground_collision_proven") is True, "ground proof lost")
    require(source.get("source_sightline_clear") is True, "sightline proof lost")

    review = data.get("human_review", {})
    reasons = review.get("blocking_reasons", [])
    require(review.get("status") == "reject", "visually rejected frame was silently accepted")
    require(review.get("full_frame_inspected") is True, "full-frame review proof missing")
    require(review.get("road_identity_matches_frame") is True, "road identity must stay distinguished from pose defect")
    require("player_pose_t_pose" in reasons, "T-pose rejection reason missing")

    auth = data.get("authorization", {})
    for key in ("qa_witness_accepted", "playability_claimed", "destination_advertisable", "jouable_authorized"):
        require(auth.get(key) is False, f"{key} must remain fail-closed while human review is REJECT")

    road_test = ROAD_TEST.read_text(encoding="utf-8")
    require("AUTOMATIC_ROAD_RUNTIME_READY_GREEN:" in road_test, "route-ready marker missing")
    require("AUTOMATIC_ROAD_PLAYER_WITNESS_HOLD:" in road_test, "player-witness HOLD marker missing")
    require("_authored_animation_driver_state" not in road_test, "route proof still inspects Character animation")

    workflow = ROAD_WORKFLOW.read_text(encoding="utf-8")
    require('grep -F "AUTOMATIC_ROAD_RUNTIME_READY_GREEN"' in workflow, "route workflow does not require route-ready proof")
    require('grep -F "animation_driver="' not in workflow, "route workflow still requires Character animation")

    witness_test = PLAYER_WITNESS_TEST.read_text(encoding="utf-8")
    require("_authored_animation_driver_state" in witness_test, "dedicated witness does not inspect authored animation")
    require("AnimationPlayer" in witness_test and "AnimationTree" in witness_test, "animation driver types not inspected")
    require("active_driver_count" in witness_test, "active animation drivers not counted")
    require("authored player animation driver inactive; refusing bind/T-pose player-view witness" in witness_test, "inactive authored animation does not fail closed")
    require("ANIMATION_DIAGNOSTIC_PATH" in witness_test, "machine-readable animation diagnostic path missing")
    require("_write_animation_diagnostic" in witness_test, "animation diagnostic writer missing")
    require("animation_player_count" in witness_test and "animation_tree_count" in witness_test, "diagnostic lacks driver inventory")
    require("playability_claimed" in witness_test and "destination_advertisable" in witness_test, "diagnostic does not preserve authorization HOLD")

    witness_workflow = PLAYER_WITNESS_WORKFLOW.read_text(encoding="utf-8")
    require('grep -F "animation_driver="' in witness_workflow, "successful witness does not require animation provenance")
    require("automatic_road_359177328_player_animation_diagnostic.json" in witness_workflow, "rejected witness diagnostic is not staged")
    require("evidence-sha256.txt" in witness_workflow, "rejected witness evidence has no SHA-256 sidecar")
    require("sha256sum --check evidence-sha256.txt" in witness_workflow, "diagnostic sidecar is not self-verified")
    require("if-no-files-found: error" in witness_workflow, "artifact upload must fail on truly missing evidence")

    print("AUTOMATIC_ROAD_PLAYER_VISUAL_GATE_OK: review=REJECT blocker=player_pose_t_pose route_gate_separated=true animation_diagnostic_preserved=true qa_witness_accepted=false destination_advertisable=false jouable=false")


if __name__ == "__main__":
    main()
