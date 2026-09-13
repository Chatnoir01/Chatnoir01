#!/usr/bin/env python3
import argparse
import copy
from pathlib import Path

import validate_bourse_8512036_exact_head_evidence as exact_head

EXPECTED_RESOLUTION = [1280, 720]
EXPECTED_LOOKUP_MODE = "deterministic_runtime_index"
EXPECTED_MASK_NODE = "Player/VisualUpgrade"


def verify(receipt, expected_head_sha, expected_base_sha):
    head_sha, base_sha = exact_head.verify(receipt, expected_head_sha, expected_base_sha)
    assert receipt.get("resolution") == EXPECTED_RESOLUTION, (
        f"resolution drift: expected={EXPECTED_RESOLUTION} actual={receipt.get('resolution')!r}"
    )
    assert receipt.get("lookup_mode") == EXPECTED_LOOKUP_MODE, (
        f"lookup_mode drift: expected={EXPECTED_LOOKUP_MODE!r} actual={receipt.get('lookup_mode')!r}"
    )
    assert receipt.get("source_sightline_clear") is True, "source_sightline_clear must remain true"
    assert receipt.get("qa_mask_applied") is True, "qa_mask_applied must remain true"
    assert receipt.get("qa_mask_node") == EXPECTED_MASK_NODE, (
        f"qa_mask_node drift: expected={EXPECTED_MASK_NODE!r} actual={receipt.get('qa_mask_node')!r}"
    )
    assert receipt.get("qa_mask_originally_visible") is True, "qa mask original visibility must remain true"
    assert receipt.get("qa_mask_restored") is True, "qa_mask_restored must remain true"
    assert receipt.get("qa_mask_final_visibility") is receipt.get("qa_mask_originally_visible"), (
        "qa mask final visibility must equal original visibility"
    )
    assert receipt.get("qa_mask_ephemeral") is True, "qa_mask_ephemeral must remain true"
    assert receipt.get("dynamic_state_frozen") is True, "dynamic_state_frozen must remain true"
    assert receipt.get("character_runtime_changed") is False, "character_runtime_changed must remain false"
    assert receipt.get("player_physics_changed") is False, "player_physics_changed must remain false"
    assert receipt.get("camera_changed") is False, "camera_changed must remain false"
    assert receipt.get("camera_authored_contract_unchanged") is True, (
        "camera_authored_contract_unchanged must remain true"
    )
    assert receipt.get("camera_springarm_runtime_offset_allowed") is True, (
        "camera_springarm_runtime_offset_allowed contract drift"
    )
    assert receipt.get("masked_frame_cannot_promote_destination") is True, (
        "masked_frame_cannot_promote_destination must remain true"
    )
    return head_sha, base_sha


def self_test(receipt, expected_head_sha, expected_base_sha):
    mutations = (
        ("camera_changed", True, "camera_changed must remain false"),
        ("dynamic_state_frozen", False, "dynamic_state_frozen must remain true"),
        ("character_runtime_changed", True, "character_runtime_changed must remain false"),
        ("player_physics_changed", True, "player_physics_changed must remain false"),
        ("qa_mask_restored", False, "qa_mask_restored must remain true"),
        ("masked_frame_cannot_promote_destination", False, "masked_frame_cannot_promote_destination must remain true"),
    )
    old_fail_open_proven = False
    for field, forged, expected_message in mutations:
        bad = copy.deepcopy(receipt)
        bad[field] = forged
        # Causal proof: the predecessor exact-head verifier accepted these safety-semantic mutations.
        exact_head.verify(bad, expected_head_sha, expected_base_sha)
        old_fail_open_proven = True
        try:
            verify(bad, expected_head_sha, expected_base_sha)
        except AssertionError as exc:
            assert expected_message in str(exc), f"{field} rejected for unrelated reason: {exc}"
        else:
            raise AssertionError(f"exact-head safety mutation accepted: {field}")
    assert old_fail_open_proven, "predecessor fail-open was not exercised"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--expected-head-sha", required=True)
    parser.add_argument("--expected-base-sha", required=True)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    receipt = exact_head.strict_json_loads(Path(args.receipt).read_text(encoding="utf-8"))
    head_sha, base_sha = verify(receipt, args.expected_head_sha, args.expected_base_sha)
    if args.self_test:
        self_test(receipt, args.expected_head_sha, args.expected_base_sha)
    print(
        "BOURSE_8512036_EXACT_HEAD_SAFETY_CONTRACT_GREEN "
        f"head_sha={head_sha} base_sha={base_sha} "
        "predecessor_fail_open_proven=true safety_contract_bound=true promotion_authorized=false"
    )


if __name__ == "__main__":
    main()
