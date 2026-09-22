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
    assert len(result["reviewed_head_sha"]) == 40
    assert result["frame_count"] == 4
    assert result["visual_approval_claimed"] is False


def test_rejects_invalid_review_head_binding():
    gate = _gate()
    gate["latest_human_review"]["head_sha"] = "not-a-sha"
    with pytest.raises(HumanReviewValidationError, match="head sha"):
        validate_human_review(gate)


def test_rejects_invalid_artifact_and_manifest_hashes():
    gate = _gate()
    gate["latest_human_review"]["artifact_digest"] = "sha256:deadbeef"
    with pytest.raises(HumanReviewValidationError, match="artifact digest"):
        validate_human_review(gate)

    gate = _gate()
    gate["latest_human_review"]["manifest_sha256"] = "deadbeef"
    with pytest.raises(HumanReviewValidationError, match="manifest sha256"):
        validate_human_review(gate)


def test_rejects_missing_or_malformed_frame_hashes():
    gate = _gate()
    first = next(iter(gate["latest_human_review"]["png_sha256"]))
    gate["latest_human_review"]["png_sha256"][first] = "deadbeef"
    with pytest.raises(HumanReviewValidationError, match="frame sha256"):
        validate_human_review(gate)


def test_rejects_duplicate_frame_hashes():
    gate = _gate()
    names = list(gate["latest_human_review"]["png_sha256"])
    hashes = gate["latest_human_review"]["png_sha256"]
    hashes[names[1]] = hashes[names[0]]
    with pytest.raises(HumanReviewValidationError, match="distinct frame"):
        validate_human_review(gate)


def test_rejects_false_full_frame_claim_and_unknown_view_verdict():
    gate = _gate()
    gate["latest_human_review"]["full_frame_inspected"] = False
    with pytest.raises(HumanReviewValidationError, match="full-frame"):
        validate_human_review(gate)

    gate = _gate()
    first = next(iter(gate["latest_human_review"]["view_verdicts"]))
    gate["latest_human_review"]["view_verdicts"][first] = "pass"
    with pytest.raises(HumanReviewValidationError, match="view verdict"):
        validate_human_review(gate)


def test_rejects_review_resolution_or_source_mutation_claims():
    gate = _gate()
    gate["latest_human_review"]["resolution"] = [640, 360]
    with pytest.raises(HumanReviewValidationError, match="resolution"):
        validate_human_review(gate)

    gate = _gate()
    gate["latest_human_review"]["source_geometry_changed"] = True
    with pytest.raises(HumanReviewValidationError, match="source geometry"):
        validate_human_review(gate)


def test_overall_keep_requires_explicit_keep_for_all_required_views():
    gate = _gate()
    gate["latest_human_review"]["overall_verdict"] = "keep"
    gate["latest_human_review"]["view_verdicts"] = {
        view_id: "keep" for view_id in gate["evidence_contract"]["required_view_ids"]
    }
    result = validate_human_review(gate)
    assert result["overall_verdict"] == "keep"
    assert result["visual_approval_claimed"] is False

    gate = _gate()
    gate["latest_human_review"]["overall_verdict"] = "keep"
    gate["latest_human_review"]["view_verdicts"] = {"canonical": "keep"}
    with pytest.raises(HumanReviewValidationError, match="all required views"):
        validate_human_review(gate)


def test_reject_overall_requires_at_least_one_rejected_view():
    gate = _gate()
    gate["latest_human_review"]["view_verdicts"] = {"canonical": "keep"}
    gate["latest_human_review"]["overall_verdict"] = "reject"
    with pytest.raises(HumanReviewValidationError, match="rejected view"):
        validate_human_review(gate)
