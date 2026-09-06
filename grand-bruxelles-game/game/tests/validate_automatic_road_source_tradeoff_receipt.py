import argparse
import json
import math
import re
from pathlib import Path


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
CANDIDATE_INT_FIELDS = ("segment", "side", "along", "continuation", "hits")
CANDIDATE_FLOAT_FIELDS = ("fraction", "offset", "lookahead", "view_clearance", "spawn_clearance")
# Candidate clearances are intentionally serialized to 3 decimal places by the
# Godot diagnostic while the aggregate ratio is serialized to 6 decimals. A
# 1e-6 ratio check is therefore stricter than the receipt's own numeric
# precision and can reject an internally consistent receipt. The 5e-6 bound is
# the propagated worst-case quantization error for this measured pair, and is
# still orders of magnitude below the frozen 1 mm gameplay safety epsilon.
RELATIVE_GAP_ABS_TOLERANCE = 5e-6


def fail(message: str) -> None:
    raise SystemExit(f"AUTOMATIC_ROAD_SOURCE_TRADEOFF_RECEIPT_FAIL: {message}")


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def close(a: float, b: float, tolerance: float = 1e-6) -> bool:
    return math.isclose(a, b, rel_tol=0.0, abs_tol=tolerance)


def require_finite_number(value: object, field: str) -> float:
    require(type(value) in (int, float), f"{field} must be numeric")
    numeric = float(value)
    require(math.isfinite(numeric), f"{field} must be finite")
    return numeric


def validate_candidate(name: str, value: object) -> dict:
    require(isinstance(value, dict), f"{name} must be an object")
    candidate = value
    for field in CANDIDATE_INT_FIELDS:
        require(type(candidate.get(field)) is int, f"{name}.{field} must be an integer")
    for field in CANDIDATE_FLOAT_FIELDS:
        require_finite_number(candidate.get(field), f"{name}.{field}")
    require(candidate["segment"] >= 0, f"{name}.segment must be non-negative")
    require(candidate["side"] in (-1, 1), f"{name}.side must be -1 or +1")
    require(candidate["along"] in (-1, 1), f"{name}.along must be -1 or +1")
    require(0.0 <= float(candidate["fraction"]) <= 1.0, f"{name}.fraction must be within [0,1]")
    require(float(candidate["offset"]) > 0.0, f"{name}.offset must be positive")
    require(float(candidate["lookahead"]) > 0.0, f"{name}.lookahead must be positive")
    require(float(candidate["view_clearance"]) >= 0.0, f"{name}.view_clearance must be non-negative")
    require(float(candidate["spawn_clearance"]) >= 0.0, f"{name}.spawn_clearance must be non-negative")
    require(candidate["continuation"] >= 0, f"{name}.continuation must be non-negative")
    require(0 <= candidate["hits"] <= 3, f"{name}.hits must be within [0,3]")
    return candidate


def validate(payload: object) -> None:
    require(isinstance(payload, dict), "receipt root must be an object")
    data = payload

    required_strings = (
        "head_sha",
        "source_document_path",
        "source_document_sha256",
        "source_format",
        "source_provenance",
        "source_license",
        "runtime_index_path",
        "runtime_index_sha256",
        "runtime_index_format",
        "source_handoff_reason",
        "policy",
        "decision",
    )
    for field in required_strings:
        require(isinstance(data.get(field), str) and data[field], f"{field} must be a non-empty string")

    require(SHA256_RE.fullmatch(data["source_document_sha256"]) is not None, "source_document_sha256 must be lowercase SHA-256")
    require(SHA256_RE.fullmatch(data["runtime_index_sha256"]) is not None, "runtime_index_sha256 must be lowercase SHA-256")
    require(re.fullmatch(r"[0-9a-f]{40}", data["head_sha"]) is not None, "head_sha must be a full lowercase Git SHA")
    require(type(data.get("road_id")) is int and data["road_id"] > 0, "road_id must be a positive integer")

    safest = validate_candidate("safest_candidate", data.get("safest_candidate"))
    balanced = validate_candidate("best_balanced_candidate", data.get("best_balanced_candidate"))

    clearance_gap = require_finite_number(data.get("clearance_gap_m"), "clearance_gap_m")
    recovery = require_finite_number(data.get("required_safety_recovery_m"), "required_safety_recovery_m")
    relative_gap = require_finite_number(data.get("relative_gap"), "relative_gap")
    epsilon = require_finite_number(data.get("epsilon_m"), "epsilon_m")
    safest_clearance = float(safest["view_clearance"])
    balanced_clearance = float(balanced["view_clearance"])

    require(epsilon > 0.0, "epsilon_m must be positive")
    require(clearance_gap > epsilon, "clearance gap must remain above frozen safety epsilon")
    require(close(clearance_gap, safest_clearance - balanced_clearance, 1e-3), "clearance_gap_m disagrees with candidate clearances")
    require(close(recovery, clearance_gap - epsilon), "required_safety_recovery_m arithmetic mismatch")
    require(safest_clearance > 0.0, "safest view clearance must be positive")
    require(
        close(relative_gap, clearance_gap / safest_clearance, RELATIVE_GAP_ABS_TOLERANCE),
        "relative_gap arithmetic mismatch beyond serialized-clearance quantization bound",
    )

    require(safest["hits"] == 0, "safest candidate must remain visually barren for this blocker classification")
    require(balanced["hits"] in (1, 2), "balanced candidate must satisfy the frozen 1-2 building-hit contract")
    require(safest_clearance > balanced_clearance, "balanced candidate must trade source-view safety for context")

    require(data.get("safest_continuation") == safest["continuation"], "safest_continuation disagrees with safest candidate")
    require(data.get("balanced_continuation") == balanced["continuation"], "balanced_continuation disagrees with balanced candidate")
    require(data.get("balanced_continuation_gain") == balanced["continuation"] - safest["continuation"], "balanced_continuation_gain arithmetic mismatch")

    exact_values = {
        "source_format": "grand-bruxelles-osm-v1",
        "source_provenance": "OpenStreetMap contributors via Overpass API",
        "source_license": "ODbL-1.0",
        "runtime_index_format": "grand-bruxelles-road-runtime-index-v1",
        "source_handoff_reason": "BALANCED_CONTEXT_REQUIRES_SOURCE_VIEW_SAFETY_LOSS_GT_EPSILON",
        "policy": "SOURCE_VIEW_CORRIDOR_SAFETY_PRECEDES_NETWORK_CONTINUATION_AND_VISUAL_CONTEXT",
        "decision": "KEEP_SOURCE_VIEW_SAFETY_PRIMARY_AND_ROUTE_CONTEXT_BLOCKER_TO_SOURCE_COVERAGE_QA",
    }
    for field, expected in exact_values.items():
        require(data.get(field) == expected, f"{field} changed: expected {expected!r}")

    fail_closed = {
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
    for field, expected in fail_closed.items():
        require(data.get(field) is expected, f"{field} must remain {expected}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("receipt", type=Path)
    args = parser.parse_args()
    payload = json.loads(args.receipt.read_text(encoding="utf-8"))
    validate(payload)
    print("AUTOMATIC_ROAD_SOURCE_TRADEOFF_RECEIPT_GREEN")


if __name__ == "__main__":
    main()
