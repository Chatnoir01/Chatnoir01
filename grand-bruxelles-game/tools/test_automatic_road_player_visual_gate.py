#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

GATE = Path("grand-bruxelles-game/data/qa/automatic_road_player_visual_gate.json")
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

    print(
        "AUTOMATIC_ROAD_PLAYER_VISUAL_GATE_OK: "
        "road=408211693 review=REJECT blocker=player_pose_t_pose "
        "qa_witness_accepted=false destination_advertisable=false jouable=false"
    )


if __name__ == "__main__":
    main()
