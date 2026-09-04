#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REVIEW = ROOT / "data" / "qa" / "grand_place_complete_contour_multiview_review.json"
REQUIRED_VIEWS = {"canonical.png", "quarter_left.png", "opposite.png", "quarter_right.png"}
GIT_SHA = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise AssertionError(message)


raw = json.loads(REVIEW.read_text(encoding="utf-8"))
if raw.get("schema") != "grand-bruxelles-grand-place-complete-contour-multiview-review-v1":
    fail("multiview review schema drifted")

capture_head = raw.get("capture_head_sha")
if not isinstance(capture_head, str) or not GIT_SHA.fullmatch(capture_head):
    fail("capture head SHA must be an exact 40-hex Git commit id")
if not isinstance(raw.get("workflow_run_id"), int) or raw["workflow_run_id"] <= 0:
    fail("workflow run id missing")
if not isinstance(raw.get("artifact_id"), int) or raw["artifact_id"] <= 0:
    fail("artifact id missing")
artifact_digest = raw.get("artifact_digest")
if not isinstance(artifact_digest, str) or not artifact_digest.startswith("sha256:") or not SHA256.fullmatch(artifact_digest[7:]):
    fail("artifact digest invalid")
if raw.get("resolution") != [1280, 720]:
    fail("review resolution drifted")
if raw.get("full_frame_inspected") is not True:
    fail("full-frame inspection is mandatory")
for rail in ("source_geometry_modified", "collision_modified", "camera_modified_after_capture", "visual_acceptance", "jouable_authorized"):
    if raw.get(rail) is not False:
        fail(f"authorization rail must remain false: {rail}")

views = raw.get("views")
if not isinstance(views, dict) or set(views) != REQUIRED_VIEWS:
    fail("review must contain exactly the four frozen views")
seen_hashes = set()
rejected = []
for name in sorted(REQUIRED_VIEWS):
    entry = views.get(name)
    if not isinstance(entry, dict):
        fail(f"missing review entry: {name}")
    digest = entry.get("sha256")
    if not isinstance(digest, str) or not SHA256.fullmatch(digest):
        fail(f"invalid PNG SHA-256: {name}")
    if digest in seen_hashes:
        fail("distinct frozen views must not share a PNG digest")
    seen_hashes.add(digest)
    verdict = entry.get("verdict")
    if verdict not in {"KEEP", "REJECT"}:
        fail(f"invalid view verdict: {name}")
    reason = entry.get("reason")
    if not isinstance(reason, str) or len(reason.strip()) < 16:
        fail(f"review reason too weak: {name}")
    if verdict == "REJECT":
        rejected.append(name)

overall = raw.get("overall_witness_verdict")
if overall not in {"KEEP", "REJECT"}:
    fail("invalid overall witness verdict")
if overall == "KEEP" and rejected:
    fail("overall KEEP cannot contain a rejected view")
if overall == "REJECT" and not rejected:
    fail("overall REJECT requires at least one rejected view")

# The first inspected campaign is intentionally a rejected witness: keeping this
# assertion makes the current evidence impossible to silently reinterpret as a
# visual pass while the frozen quarter-left view remains unusable.
if overall != "REJECT" or "quarter_left.png" not in rejected:
    fail("current reviewed witness rejection was weakened")

print(
    "GRAND_PLACE_MULTIVIEW_REVIEW_CONTRACT_GREEN "
    f"capture_head={capture_head} rejected={','.join(rejected)} visual_acceptance=false jouable=false"
)
