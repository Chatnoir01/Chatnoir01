#!/usr/bin/env python3
"""Fail-closed provenance guard for the historical Bourse owner-review candidate.

This guard does not promote or reconstruct the candidate. It records the live-main
truth that Bourse exact-location presentation remains owned by PR #880 and that
Shared Environment must not silently absorb its stale implementation history.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECEIPT = ROOT / "data/qa/bourse_owner_review_candidate_provenance.json"

EXPECTED_KEYS = {
    "schema",
    "live_main_sha",
    "owner_pr",
    "owner_head_sha",
    "owner_base_sha",
    "candidate_status",
    "source_basis",
    "frozen_gate",
    "shared_environment_authorized",
    "runtime_merge_authorized",
    "visual_acceptance",
    "jouable_authorized",
    "next_action",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"BOURSE_OWNER_REVIEW_PROVENANCE_FAIL: {message}")


def main() -> None:
    require(RECEIPT.is_file(), "receipt missing")
    data = json.loads(RECEIPT.read_text(encoding="utf-8"))
    require(type(data) is dict, "receipt must be an object")
    require(set(data) == EXPECTED_KEYS, "receipt keyset drift")
    require(data["schema"] == "grand-bruxelles-bourse-owner-review-provenance-v1", "schema drift")
    require(data["live_main_sha"] == "8938792700837c6e53bf9661f0c304dfeba84897", "live-main identity drift")
    require(data["owner_pr"] == 880, "Bourse owner PR drift")
    require(data["owner_head_sha"] == "98b0d73fda776810c4cd20e244c209393d6d21d1", "owner head drift")
    require(data["owner_base_sha"] == "0807581e4a711d21b535a7def66f089da037a2f4", "owner base drift")
    require(data["candidate_status"] == "OPEN_DRAFT_STALE_OWNER_REVIEW", "candidate status drift")
    source = data["source_basis"]
    require(type(source) is dict and set(source) == {"heritage_record", "heritage_fact"}, "source basis drift")
    require(source["heritage_record"] == "A001/31241", "heritage record drift")
    require("triangular pediment" in source["heritage_fact"], "heritage fact lost")
    gate = data["frozen_gate"]
    require(type(gate) is dict and set(gate) == {"changed_gt3", "changed_gt3_min", "changed_gt8", "changed_gt8_min", "bbox_px", "bbox_min_px"}, "gate keyset drift")
    require(gate == {
        "changed_gt3": 0.008575,
        "changed_gt3_min": 0.01,
        "changed_gt8": 0.0084,
        "changed_gt8_min": 0.005,
        "bbox_px": [616, 426],
        "bbox_min_px": [500, 40],
    }, "frozen owner-review measurements drift")
    for key in ("shared_environment_authorized", "runtime_merge_authorized", "visual_acceptance", "jouable_authorized"):
        require(data[key] is False, f"{key} must remain false")
    require(data["next_action"] == "OWNER_REVIEW_OR_CLEAN_CURRENT_MAIN_REBUILD_BY_BOURSE_OWNER", "next action drift")
    print("BOURSE_OWNER_REVIEW_PROVENANCE_OK")


if __name__ == "__main__":
    main()
