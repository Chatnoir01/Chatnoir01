#!/usr/bin/env python3
import argparse
import copy
import json
import math
import re
import tempfile
from pathlib import Path

SCHEMA = "grand-bruxelles-bourse-8512036-corridor-masked-visual-v1"
ROAD_ID = 8512036
SOURCE_PATH = "res://data/osm/vertical_slice_01.game.json"
SOURCE_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
RECEIPT_FIELDS = frozenset({
    "schema", "road_osm_id", "request", "resolution", "source_path", "source_sha256",
    "source_name", "lookup_mode", "spawn_xz", "target_xz", "ground_y", "camera_fov",
    "segment_index", "axis_alignment", "source_sightline_clear", "qa_mask_applied",
    "qa_mask_node", "qa_mask_originally_visible", "qa_mask_restored", "qa_mask_final_visibility",
    "qa_mask_ephemeral", "dynamic_state_frozen", "character_runtime_changed",
    "player_physics_changed", "camera_changed", "camera_authored_contract_unchanged",
    "camera_springarm_runtime_offset_allowed", "source_geometry_changed",
    "collision_geometry_changed", "resolver_thresholds_lowered", "human_visual_review_required",
    "masked_frame_cannot_promote_destination", "visual_acceptance", "destination_advertisable",
    "jouable_authorized", "head_sha", "base_sha",
})


def strict_json_loads(raw):
    def no_duplicates(pairs):
        out = {}
        for key, value in pairs:
            if key in out:
                raise ValueError(f"duplicate JSON key: {key}")
            out[key] = value
        return out

    def reject_constant(token):
        raise ValueError(f"non-standard JSON constant: {token}")

    def finite_float(token):
        value = float(token)
        if not math.isfinite(value):
            raise ValueError(f"non-finite JSON number: {token}")
        return value

    value = json.loads(
        raw,
        object_pairs_hook=no_duplicates,
        parse_constant=reject_constant,
        parse_float=finite_float,
    )
    if not isinstance(value, dict):
        raise ValueError(f"receipt JSON root must be an object, got {type(value).__name__}")
    return value


def require_git_sha(value, label):
    assert isinstance(value, str) and HEX40.fullmatch(value), f"{label} malformed: {value!r}"
    return value


def seal_receipt(path, expected_head_sha, expected_base_sha):
    expected_head_sha = require_git_sha(expected_head_sha, "expected head SHA")
    expected_base_sha = require_git_sha(expected_base_sha, "expected base SHA")
    receipt = strict_json_loads(path.read_text(encoding="utf-8"))
    assert "head_sha" not in receipt, "producer receipt unexpectedly contains head_sha before sealing"
    assert "base_sha" not in receipt, "producer receipt unexpectedly contains base_sha before sealing"
    receipt["head_sha"] = expected_head_sha
    receipt["base_sha"] = expected_base_sha
    path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return receipt


def verify(receipt, expected_head_sha, expected_base_sha):
    expected_head_sha = require_git_sha(expected_head_sha, "expected head SHA")
    expected_base_sha = require_git_sha(expected_base_sha, "expected base SHA")
    actual_fields = set(receipt)
    unexpected = sorted(actual_fields - RECEIPT_FIELDS)
    missing = sorted(RECEIPT_FIELDS - actual_fields)
    assert not unexpected, f"unexpected receipt fields: {unexpected}"
    assert not missing, f"missing receipt fields: {missing}"

    receipt_head = require_git_sha(receipt.get("head_sha"), "receipt head SHA")
    receipt_base = require_git_sha(receipt.get("base_sha"), "receipt base SHA")

    assert receipt.get("schema") == SCHEMA
    assert type(receipt.get("road_osm_id")) is int and receipt["road_osm_id"] == ROAD_ID
    assert receipt.get("request") == f"road-{ROAD_ID}"
    assert receipt.get("source_path") == SOURCE_PATH
    assert receipt.get("source_sha256") == SOURCE_SHA256
    assert receipt_head == expected_head_sha, (
        f"receipt head SHA drift: expected={expected_head_sha} actual={receipt_head}"
    )
    assert receipt_base == expected_base_sha, (
        f"receipt base SHA drift: expected={expected_base_sha} actual={receipt_base}"
    )
    assert receipt.get("human_visual_review_required") is True
    assert receipt.get("visual_acceptance") is False
    assert receipt.get("destination_advertisable") is False
    assert receipt.get("jouable_authorized") is False
    assert receipt.get("source_geometry_changed") is False
    assert receipt.get("collision_geometry_changed") is False
    assert receipt.get("resolver_thresholds_lowered") is False
    return receipt_head, receipt_base


def parser_self_test():
    cases = (
        ('{"probe":1e309}', "non-finite JSON number"),
        ('{"probe":-1e309}', "non-finite JSON number"),
        ('{"probe":NaN}', "non-standard JSON constant"),
        ('{"probe":1,"probe":2}', "duplicate JSON key"),
        ('[1,2,3]', "receipt JSON root must be an object"),
    )
    for raw, expected_message in cases:
        try:
            strict_json_loads(raw)
        except ValueError as exc:
            assert expected_message in str(exc), (raw, exc)
        else:
            raise AssertionError(f"invalid receipt JSON accepted by exact-head evidence parser: {raw}")


def seal_self_test(receipt, expected_head_sha, expected_base_sha):
    raw = json.dumps(receipt, separators=(",", ":"))
    assert raw.startswith("{")
    duplicate = '{"schema":"forged",' + raw[1:]
    overflow = raw[:-1] + ',"overflow_probe":1e309}'
    for label, payload, expected_message in (
        ("duplicate-key", duplicate, "duplicate JSON key: schema"),
        ("numeric-overflow", overflow, "non-finite JSON number"),
    ):
        with tempfile.TemporaryDirectory() as tmpdir:
            probe = Path(tmpdir) / f"{label}.json"
            probe.write_text(payload, encoding="utf-8")
            try:
                seal_receipt(probe, expected_head_sha, expected_base_sha)
            except ValueError as exc:
                assert expected_message in str(exc), f"{label} rejected for unrelated reason: {exc}"
            else:
                raise AssertionError(f"{label} producer receipt was normalized and sealed instead of rejected")


def self_test(receipt, expected_head_sha, expected_base_sha):
    parser_self_test()
    seal_self_test(receipt, expected_head_sha, expected_base_sha)
    for field, forged, expected_message in (
        ("head_sha", "0" * 40, "receipt head SHA drift:"),
        ("base_sha", "1" * 40, "receipt base SHA drift:"),
    ):
        assert forged != receipt[field]
        bad = copy.deepcopy(receipt)
        bad[field] = forged
        try:
            verify(bad, expected_head_sha, expected_base_sha)
        except AssertionError as exc:
            assert expected_message in str(exc), f"{field} mutation rejected for unrelated reason: {exc}"
        else:
            raise AssertionError(f"forged {field} accepted by exact-head evidence gate")

    malformed = copy.deepcopy(receipt)
    malformed["head_sha"] = expected_head_sha.upper()
    try:
        verify(malformed, expected_head_sha, expected_base_sha)
    except AssertionError as exc:
        assert "receipt head SHA malformed:" in str(exc)
    else:
        raise AssertionError("non-canonical uppercase receipt head SHA accepted")

    injected = copy.deepcopy(receipt)
    injected["runtime_mount_authorized"] = True
    try:
        verify(injected, expected_head_sha, expected_base_sha)
    except AssertionError as exc:
        assert "unexpected receipt fields:" in str(exc), f"unknown-field mutation rejected for unrelated reason: {exc}"
    else:
        raise AssertionError("unknown authorization field accepted by exact-head evidence gate")

    missing = copy.deepcopy(receipt)
    missing.pop("masked_frame_cannot_promote_destination")
    try:
        verify(missing, expected_head_sha, expected_base_sha)
    except AssertionError as exc:
        assert "missing receipt fields:" in str(exc), f"missing-field mutation rejected for unrelated reason: {exc}"
    else:
        raise AssertionError("missing canonical producer field accepted by exact-head evidence gate")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--expected-head-sha", required=True)
    parser.add_argument("--expected-base-sha", required=True)
    parser.add_argument("--seal-provenance", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    receipt_path = Path(args.receipt)
    if args.seal_provenance:
        receipt = seal_receipt(receipt_path, args.expected_head_sha, args.expected_base_sha)
    else:
        receipt = strict_json_loads(receipt_path.read_text(encoding="utf-8"))
    head_sha, base_sha = verify(receipt, args.expected_head_sha, args.expected_base_sha)
    if args.self_test:
        self_test(receipt, args.expected_head_sha, args.expected_base_sha)
    print(
        "BOURSE_8512036_EXACT_HEAD_EVIDENCE_GREEN "
        f"head_sha={head_sha} base_sha={base_sha} "
        "strict_preseal_json=true finite_json_required=true closed_receipt_schema=true "
        "human_review_required=true promotion_authorized=false"
    )


if __name__ == "__main__":
    main()
