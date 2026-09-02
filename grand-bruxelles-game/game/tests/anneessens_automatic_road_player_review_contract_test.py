#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
receipt_path = ROOT / "data" / "qa" / "anneessens_automatic_road_player_review.json"
assert receipt_path.exists(), "missing persisted Anneessens player-review receipt"
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))

assert receipt.get("format") == "grand-bruxelles-anneessens-automatic-road-player-review-v1"
assert re.fullmatch(r"[0-9a-f]{40}", receipt.get("reviewed_head_sha", "")), "invalid reviewed head"
assert isinstance(receipt.get("workflow_run_id"), int) and receipt["workflow_run_id"] > 0
assert isinstance(receipt.get("artifact_id"), int) and receipt["artifact_id"] > 0
assert re.fullmatch(r"sha256:[0-9a-f]{64}", receipt.get("artifact_digest", "")), "invalid artifact digest"

frame = receipt.get("frame", {})
assert frame.get("path") == "automatic_road_1382734012_player.png"
assert re.fullmatch(r"[0-9a-f]{64}", frame.get("sha256", "")), "invalid frame sha256"
assert (frame.get("width"), frame.get("height")) == (1280, 720)
assert frame.get("full_frame_inspected") is True

source = receipt.get("source", {})
assert source.get("osm_id") == 1382734012
assert source.get("name") == "Place Anneessens - Anneessensplein"
assert source.get("path") == "data/osm/vertical_slice_01.game.json"
assert re.fullmatch(r"[0-9a-f]{64}", source.get("sha256", "")), "invalid source sha256"

runtime = receipt.get("measured_runtime", {})
assert runtime.get("camera_unchanged") is True
assert runtime.get("camera_clip_unchanged") is True
assert runtime.get("camera_cull_mask_unchanged") is True
assert float(runtime.get("road_axis_alignment", 0.0)) >= 0.90
assert float(runtime.get("offset_m", 0.0)) > 0.0

assert receipt.get("human_verdict") == "REJECT_AS_VISUAL_ACCEPTANCE_EVIDENCE"
assert len(receipt.get("reason", "").strip()) >= 40, "visual rejection requires an explicit reason"
assert len(receipt.get("next_action", "").strip()) >= 40, "visual rejection requires an executable next action"

auth = receipt.get("authorization", {})
for key in (
    "destination_advertisable",
    "jouable_authorized",
    "visual_approval_claimed",
    "geometry_mutation_authorized",
    "camera_rescue_authorized",
    "threshold_relaxation_authorized",
):
    assert auth.get(key) is False, f"rejected Anneessens evidence must keep {key}=false"

print("ANNEESSENS_AUTOMATIC_ROAD_PLAYER_REVIEW_CONTRACT_GREEN")
