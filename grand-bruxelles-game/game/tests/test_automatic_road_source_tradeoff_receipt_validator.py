#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
VALIDATOR_PATH = ROOT / "grand-bruxelles-game/game/tests/validate_automatic_road_source_tradeoff_receipt.py"

spec = importlib.util.spec_from_file_location("tradeoff_validator", VALIDATOR_PATH)
assert spec is not None and spec.loader is not None
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def base_receipt() -> dict:
    return {
        "head_sha": "1" * 40,
        "source_document_path": "grand-bruxelles-game/data/osm/vertical_slice_01.game.json",
        "source_document_sha256": "2" * 64,
        "source_format": "grand-bruxelles-osm-v1",
        "source_provenance": "OpenStreetMap contributors via Overpass API",
        "source_license": "ODbL-1.0",
        "runtime_index_path": "grand-bruxelles-game/data/osm/road_runtime_index.json",
        "runtime_index_sha256": "3" * 64,
        "runtime_index_format": "grand-bruxelles-road-runtime-index-v1",
        "source_handoff_reason": "BALANCED_CONTEXT_REQUIRES_SOURCE_VIEW_SAFETY_LOSS_GT_EPSILON",
        "policy": "SOURCE_VIEW_CORRIDOR_SAFETY_PRECEDES_NETWORK_CONTINUATION_AND_VISUAL_CONTEXT",
        "decision": "KEEP_SOURCE_VIEW_SAFETY_PRIMARY_AND_ROUTE_CONTEXT_BLOCKER_TO_SOURCE_COVERAGE_QA",
        "road_id": 1382734012,
        "safest_candidate": {
            "segment": 2,
            "fraction": 0.35,
            "offset": 7.5,
            "side": -1,
            "along": -1,
            "lookahead": 18.0,
            "view_clearance": 10.0,
            "spawn_clearance": 10.0,
            "continuation": 0,
            "hits": 0,
        },
        "best_balanced_candidate": {
            "segment": 2,
            "fraction": 0.20,
            "offset": 3.6,
            "side": 1,
            "along": 1,
            "lookahead": 12.0,
            "view_clearance": 8.0,
            "spawn_clearance": 12.0,
            "continuation": 2,
            "hits": 2,
        },
        "clearance_gap_m": 2.0,
        "required_safety_recovery_m": 1.999,
        "relative_gap": 0.2,
        "epsilon_m": 0.001,
        "safest_continuation": 0,
        "balanced_continuation": 2,
        "balanced_continuation_gain": 2,
        "runtime_index_source_lookup_only": True,
        "safety_equivalent": False,
        "source_coverage_blocker": True,
        "resolver_mutation_allowed": False,
        "camera_unchanged": True,
        "source_only": True,
        "geometry_unchanged": True,
        "destination_advertisable": False,
        "visual_acceptance": False,
        "jouable": False,
    }


def must_pass(payload: dict, label: str) -> None:
    try:
        validator.validate(payload)
    except SystemExit as exc:
        raise AssertionError(f"{label} unexpectedly failed: {exc}") from exc


def must_fail(payload: dict, expected_fragment: str, label: str) -> None:
    try:
        validator.validate(payload)
    except SystemExit as exc:
        message = str(exc)
        if expected_fragment not in message:
            raise AssertionError(f"{label} failed for wrong reason: {message}") from exc
        return
    raise AssertionError(f"{label} unexpectedly passed")


def main() -> None:
    valid = base_receipt()
    must_pass(valid, "baseline valid blocker receipt")

    within_quantization = copy.deepcopy(valid)
    within_quantization["relative_gap"] = 0.200004
    must_pass(within_quantization, "relative-gap value inside serialized quantization bound")

    beyond_quantization = copy.deepcopy(valid)
    beyond_quantization["relative_gap"] = 0.200006
    must_fail(
        beyond_quantization,
        "relative_gap arithmetic mismatch beyond serialized-clearance quantization bound",
        "relative-gap value outside serialized quantization bound",
    )

    nonfinite_candidate = copy.deepcopy(valid)
    nonfinite_candidate["safest_candidate"]["spawn_clearance"] = float("inf")
    must_fail(
        nonfinite_candidate,
        "safest_candidate.spawn_clearance must be finite",
        "non-finite candidate measurement",
    )

    nonfinite_aggregate = copy.deepcopy(valid)
    nonfinite_aggregate["safest_candidate"]["view_clearance"] = float("inf")
    nonfinite_aggregate["clearance_gap_m"] = float("inf")
    nonfinite_aggregate["required_safety_recovery_m"] = float("inf")
    nonfinite_aggregate["relative_gap"] = float("inf")
    must_fail(
        nonfinite_aggregate,
        "safest_candidate.view_clearance must be finite",
        "non-finite aggregate arithmetic",
    )

    fail_open = copy.deepcopy(valid)
    fail_open["resolver_mutation_allowed"] = True
    must_fail(fail_open, "resolver_mutation_allowed must remain False", "fail-open resolver authorization")

    continuation_tamper = copy.deepcopy(valid)
    continuation_tamper["balanced_continuation_gain"] = 1
    must_fail(continuation_tamper, "balanced_continuation_gain arithmetic mismatch", "continuation arithmetic tamper")

    source_identity_tamper = copy.deepcopy(valid)
    source_identity_tamper["source_format"] = "grand-bruxelles-osm-v2"
    must_fail(source_identity_tamper, "source_format changed", "source-format tamper")

    unsafe_reclassification = copy.deepcopy(valid)
    unsafe_reclassification["safest_candidate"]["hits"] = 1
    must_fail(
        unsafe_reclassification,
        "safest candidate must remain visually barren for this blocker classification",
        "blocker reclassification without renewed evidence",
    )

    print("AUTOMATIC_ROAD_SOURCE_TRADEOFF_RECEIPT_VALIDATOR_TEST_GREEN")


if __name__ == "__main__":
    main()
