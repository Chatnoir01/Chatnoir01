#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import struct
from pathlib import Path

from strict_json_evidence import load_path_strict

ROOT = Path(__file__).resolve().parents[2]
RECEIPT = ROOT / "data/qa/corridor/bourse_8512036_human_review.json"
REVIEWED_HEAD = "2c56c997071f4c90204d330a16f40863900e60dc"
WORKFLOW_RUN_ID = 34738947794
ARTIFACT_ID = 10312386121
ARTIFACT_NAME = "grand-bruxelles-bourse-8512036-corridor-masked-visual"
ARTIFACT_DIGEST = "sha256:bbbda2bccb09c3ea07f7af0f39118487272c215abf90ea6722fd93035e97b0d1"
PNG_SHA256 = "9ead5aefb244092c96143366e01c9f3ff321c480d4197ca87e441efcbfcf61f2"
OSM_ID = 8512036
WIDTH = 1280
HEIGHT = 720


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def png_dimensions(path: Path) -> tuple[int, int]:
    payload = path.read_bytes()
    require(len(payload) >= 24, "reviewed PNG truncated")
    require(payload[:8] == b"\x89PNG\r\n\x1a\n", "reviewed file is not PNG")
    require(payload[12:16] == b"IHDR", "reviewed PNG missing IHDR")
    return struct.unpack(">II", payload[16:24])


def main() -> None:
    require(RECEIPT.is_file(), "human review receipt missing")
    receipt = load_path_strict(RECEIPT)
    require(isinstance(receipt, dict), "receipt must be an object")
    require(receipt.get("schema") == "grand-bruxelles-bourse-8512036-human-review-v1", "schema drift")
    require(receipt.get("reviewed_head_sha") == REVIEWED_HEAD, "reviewed head drift")
    require(receipt.get("workflow_run_id") == WORKFLOW_RUN_ID, "workflow run drift")
    require(receipt.get("artifact_id") == ARTIFACT_ID, "artifact id drift")
    require(receipt.get("artifact_name") == ARTIFACT_NAME, "artifact name drift")
    require(receipt.get("artifact_digest") == ARTIFACT_DIGEST, "artifact digest drift")
    require(receipt.get("png_sha256") == PNG_SHA256, "png digest drift")
    require(receipt.get("osm_id") == OSM_ID, "OSM identity drift")
    require(receipt.get("source_name") == "Rue Saint-Géry - Sint-Goriksstraat", "source name drift")
    require(receipt.get("width") == WIDTH and receipt.get("height") == HEIGHT, "review frame must remain 1280x720")
    require(receipt.get("full_frame_inspected") is True, "full-frame inspection must be explicit")
    require(receipt.get("verdict") == "REJECT", "current reviewed frame must remain REJECT")
    reasons = receipt.get("rejection_reasons")
    require(isinstance(reasons, list) and len(reasons) >= 1 and all(isinstance(v, str) and v.strip() for v in reasons), "rejection reasons required")
    require(receipt.get("camera_changed") is False, "camera rescue forbidden")
    require(receipt.get("source_geometry_changed") is False, "source geometry rescue forbidden")
    require(receipt.get("resolver_thresholds_lowered") is False, "resolver threshold rescue forbidden")
    for key in ("destination_advertisable", "visual_acceptance", "jouable_authorized"):
        require(receipt.get(key) is False, f"{key} must remain false")

    # A durable REJECT receipt is intentionally independent of current branch
    # ancestry. Corridor snapshot rebuilds re-parent proven trees directly onto
    # live main, so the reviewed head can legitimately stop being an ancestor.
    # Provenance is instead bound fail-closed below to immutable GitHub artifact
    # metadata (run + reviewed head + artifact digest) and the downloaded PNG
    # bytes. A REJECT receipt can never promote the current head.
    metadata_path = os.environ.get("BOURSE_8512036_ARTIFACT_METADATA", "").strip()
    reviewed_png_path = os.environ.get("BOURSE_8512036_REVIEWED_PNG", "").strip()
    in_github_actions = os.environ.get("GITHUB_ACTIONS", "").strip().lower() == "true"
    if in_github_actions:
        require(metadata_path, "GitHub Actions provenance gate must provide immutable artifact metadata")
        require(reviewed_png_path, "GitHub Actions provenance gate must provide downloaded reviewed PNG payload")

    if metadata_path:
        metadata = load_path_strict(Path(metadata_path))
        require(metadata.get("id") == ARTIFACT_ID, "live artifact id mismatch")
        require(metadata.get("name") == ARTIFACT_NAME, "live artifact name mismatch")
        require(metadata.get("digest") == ARTIFACT_DIGEST, "live artifact digest mismatch")
        workflow = metadata.get("workflow_run")
        require(isinstance(workflow, dict), "live artifact workflow metadata missing")
        require(workflow.get("id") == WORKFLOW_RUN_ID, "live workflow run mismatch")
        require(workflow.get("head_sha") == REVIEWED_HEAD, "live artifact head mismatch")

    if reviewed_png_path:
        reviewed_png = Path(reviewed_png_path)
        require(reviewed_png.is_file(), "reviewed PNG missing from downloaded artifact")
        payload = reviewed_png.read_bytes()
        require(hashlib.sha256(payload).hexdigest() == PNG_SHA256, "downloaded reviewed PNG digest mismatch")
        require(png_dimensions(reviewed_png) == (WIDTH, HEIGHT), "downloaded reviewed PNG dimensions mismatch")

    print(
        "BOURSE_8512036_HUMAN_REVIEW_RECEIPT_OK "
        "verdict=REJECT visual_acceptance=false jouable_authorized=false "
        "finite_json_required=true durable_reject_ancestry_independent=true "
        f"artifact_payload_verified={str(bool(reviewed_png_path)).lower()} "
        f"ci_payload_required={str(in_github_actions).lower()}"
    )


if __name__ == "__main__":
    main()
