#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
receipt_path = ROOT / "data" / "qa" / "anneessens_automatic_road_player_review.json"
assert receipt_path.exists(), "missing persisted Anneessens player-review receipt"
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))


def require_nonzero_hex(value: object, length: int, label: str) -> str:
    assert isinstance(value, str) and re.fullmatch(rf"[0-9a-f]{{{length}}}", value), f"invalid {label}"
    assert any(ch != "0" for ch in value), f"zeroed {label} sentinel is not evidence"
    return value


assert receipt.get("format") == "grand-bruxelles-anneessens-automatic-road-player-review-v1"
require_nonzero_hex(receipt.get("reviewed_head_sha"), 40, "reviewed head")
assert isinstance(receipt.get("workflow_run_id"), int) and receipt["workflow_run_id"] > 0
assert isinstance(receipt.get("artifact_id"), int) and receipt["artifact_id"] > 0
artifact_digest = receipt.get("artifact_digest", "")
assert isinstance(artifact_digest, str) and artifact_digest.startswith("sha256:"), "invalid artifact digest"
require_nonzero_hex(artifact_digest.removeprefix("sha256:"), 64, "artifact digest")

frame = receipt.get("frame", {})
assert frame.get("path") == "automatic_road_1382734012_player.png"
require_nonzero_hex(frame.get("sha256"), 64, "frame sha256")
assert (frame.get("width"), frame.get("height")) == (1280, 720)
assert frame.get("full_frame_inspected") is True

source = receipt.get("source", {})
assert source.get("osm_id") == 1382734012
assert source.get("name") == "Place Anneessens - Anneessensplein"
assert source.get("path") == "data/osm/vertical_slice_01.game.json"
require_nonzero_hex(source.get("sha256"), 64, "source sha256")

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
