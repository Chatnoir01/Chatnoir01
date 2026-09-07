#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
REQUIRED_VIEWS = {"canonical", "north_west", "north_east", "south_west", "south_east"}
REQUIRED_KEYS = {
    "schema_version",
    "reviewed_head_sha",
    "workflow_run_id",
    "artifact_id",
    "artifact_digest",
    "artifact_name",
    "manifest_sha256",
    "resolution",
    "full_frame_inspected",
    "view_sha256",
    "view_verdicts",
    "overall_verdict",
    "visual_acceptance",
    "jouable_authorized",
    "review_note",
}


def fail(message: str) -> None:
    raise SystemExit(f"GRAND_PLACE_FULL_SQUARE_HUMAN_REVIEW_FAIL: {message}")


def load_strict(path: Path):
    def no_duplicates(pairs):
        out = {}
        for key, value in pairs:
            if key in out:
                fail(f"duplicate JSON key: {key}")
            out[key] = value
        return out

    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"cannot read strict JSON receipt: {exc}")


def require_sha256(value, field: str) -> str:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        fail(f"{field} must be lowercase SHA-256")
    return value


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: validate_grand_place_full_square_human_review.py <receipt.json>")
    path = Path(sys.argv[1])
    data = load_strict(path)
    if not isinstance(data, dict):
        fail("receipt root must be an object")
    if set(data) != REQUIRED_KEYS:
        fail(f"receipt key drift: missing={sorted(REQUIRED_KEYS - set(data))} extra={sorted(set(data) - REQUIRED_KEYS)}")
    if data["schema_version"] != 1:
        fail("schema_version must be 1")
    if not isinstance(data["reviewed_head_sha"], str) or not GIT_SHA_RE.fullmatch(data["reviewed_head_sha"]):
        fail("reviewed_head_sha must be a full lowercase Git SHA")
    for field in ("workflow_run_id", "artifact_id"):
        if not isinstance(data[field], int) or data[field] <= 0:
            fail(f"{field} must be a positive integer")
    if not isinstance(data["artifact_name"], str) or data["reviewed_head_sha"] not in data["artifact_name"]:
        fail("artifact_name must bind the reviewed head SHA")
    artifact_digest = data["artifact_digest"]
    if not isinstance(artifact_digest, str) or not artifact_digest.startswith("sha256:"):
        fail("artifact_digest must use sha256:<hex>")
    require_sha256(artifact_digest.removeprefix("sha256:"), "artifact_digest")
    require_sha256(data["manifest_sha256"], "manifest_sha256")
    if data["resolution"] != [1280, 720]:
        fail("resolution must remain 1280x720")
    if data["full_frame_inspected"] is not True:
        fail("full_frame_inspected must be true")

    view_sha256 = data["view_sha256"]
    verdicts = data["view_verdicts"]
    if not isinstance(view_sha256, dict) or set(view_sha256) != REQUIRED_VIEWS:
        fail("view_sha256 must contain exactly the five frozen views")
    if not isinstance(verdicts, dict) or set(verdicts) != REQUIRED_VIEWS:
        fail("view_verdicts must contain exactly the five frozen views")
    digests = [require_sha256(view_sha256[view], f"view_sha256.{view}") for view in sorted(REQUIRED_VIEWS)]
    if len(set(digests)) != 5:
        fail("all five reviewed frames must have distinct SHA-256 values")
    allowed = {"KEEP", "REJECT"}
    if any(verdicts[view] not in allowed for view in REQUIRED_VIEWS):
        fail("view verdicts may only be KEEP or REJECT")
    if data["overall_verdict"] != "REJECT":
        fail("current human-review receipt must remain REJECT")
    if "REJECT" not in verdicts.values():
        fail("overall REJECT requires at least one rejected view")
    if data["visual_acceptance"] is not False or data["jouable_authorized"] is not False:
        fail("human-review receipt cannot open visual/JOUABLE rails")
    if not isinstance(data["review_note"], str) or len(data["review_note"].strip()) < 24:
        fail("review_note must state the visible rejection rationale")

    print(
        "GRAND_PLACE_FULL_SQUARE_HUMAN_REVIEW_OK "
        f"reviewed_head={data['reviewed_head_sha']} views=5 overall=REJECT "
        "full_frame_inspected=true visual_acceptance=false jouable_authorized=false"
    )


if __name__ == "__main__":
    main()
