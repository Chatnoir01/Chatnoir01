import copy
import json
from pathlib import Path

import pytest

from tools.qa.validate_grand_place_human_review import HumanReviewValidationError, validate_human_review

ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "data" / "qa" / "grand_place_facade_visual_gate.json"


def _gate():
    return json.loads(GATE.read_text(encoding="utf-8"))


def test_current_persisted_human_review_is_fail_closed_and_self_consistent():
    result = validate_human_review(_gate())
    assert result["overall_verdict"] == "reject"
    assert result["full_frame_inspected"] is True
    assert result["artifact_exact_head"] is True
    assert len(result["reviewed_head_sha"]) == 40
    assert result["frame_count"] == 4


def test_rejects_artifact_name_without_exact_review_head_binding():
    gate = _gate()
    gate["latest_human_review"]["artifact_name"] = "grand-place-facade-engine-evidence-not-a-sha"
    with pytest.raises(HumanReviewValidationError, match="artifact name"):
        validate_human_review(gate)


def test_rejects_invalid_artifact_and_manifest_hashes():
    gate = _gate()
    gate["latest_human_review"]["artifact_digest"] = "sha256:deadbeef"
    with pytest.raises(HumanReviewValidationError, match="artifact digest"):
        validate_human_review(gate)

    gate = _gate()
    gate["latest_human_review"]["runtime_manifest_sha256"] = "deadbeef"
    with pytest.raises(HumanReviewValidationError, match="manifest sha256"):
        validate_human_review(gate)


def test_rejects_missing_or_malformed_frame_hashes():
    gate = _gate()
    first = next(iter(gate["latest_human_review"]["frames"]))
    del gate["latest_human_review"]["frames"][first]["sha256"]
    with pytest.raises(HumanReviewValidationError, match="frame sha256"):
        validate_human_review(gate)


def test_rejects_false_full_frame_claim_and_unknown_frame_verdict():
    gate = _gate()
    gate["latest_human_review"]["full_frame_inspected"] = False
    with pytest.raises(HumanReviewValidationError, match="full-frame"):
        validate_human_review(gate)

    gate = _gate()
    first = next(iter(gate["latest_human_review"]["frames"]))
    gate["latest_human_review"]["frames"][first]["verdict"] = "pass"
    with pytest.raises(HumanReviewValidationError, match="frame verdict"):
        validate_human_review(gate)


def test_overall_verdict_must_match_frame_verdicts():
    gate = _gate()
    for frame in gate["latest_human_review"]["frames"].values():
        frame["verdict"] = "keep"
    gate["latest_human_review"]["overall_verdict"] = "reject"
    with pytest.raises(HumanReviewValidationError, match="overall verdict"):
        validate_human_review(gate)


def test_review_provenance_does_not_auto_authorize_visual_acceptance():
    gate = _gate()
    gate["latest_human_review"]["overall_verdict"] = "keep"
    for frame in gate["latest_human_review"]["frames"].values():
        frame["verdict"] = "keep"
    result = validate_human_review(gate)
    assert result["visual_approval_claimed"] is False
