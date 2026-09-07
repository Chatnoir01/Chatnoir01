#!/usr/bin/env python3
import json
import sys
from pathlib import Path

REPLAY_SAMPLES = [68, 69, 70, 71]
REQUIRED_VERTEX_COUNT = 3306


def load(path: str):
    return json.loads(Path(path).read_text())


def main() -> int:
    if len(sys.argv) != 5:
        print("CIV1_GROUND_CONTACT_FAIL:args", file=sys.stderr)
        return 2
    replay = load(sys.argv[1])
    landmark = load(sys.argv[2])
    reconstruction = load(sys.argv[3])
    output = Path(sys.argv[4])

    if replay.get("schema") != "grand-bruxelles-civ1-rightfoot-skinned-replay-v1":
        print("CIV1_GROUND_CONTACT_FAIL:replay-schema", file=sys.stderr)
        return 3
    if replay.get("sample_indices") != REPLAY_SAMPLES or replay.get("fixed_vertex_count") != REQUIRED_VERTEX_COUNT:
        print("CIV1_GROUND_CONTACT_FAIL:replay-identity", file=sys.stderr)
        return 4
    if replay.get("skinned_replay_ready") is not True or replay.get("stable_replay_sample_count", 0) < 3:
        print("CIV1_GROUND_CONTACT_FAIL:replay-not-ready", file=sys.stderr)
        return 5
    if landmark.get("schema") != "grand-bruxelles-civ1-rightfoot-landmark-witness-v1":
        print("CIV1_GROUND_CONTACT_FAIL:landmark-schema", file=sys.stderr)
        return 6
    if reconstruction.get("schema") != "grand-bruxelles-civ1-fixed-length-reconstruction-v2":
        print("CIV1_GROUND_CONTACT_FAIL:reconstruction-schema", file=sys.stderr)
        return 7

    source_ground_node = landmark.get("source_ground_node")
    source_ground_reference_present = isinstance(source_ground_node, str) and bool(source_ground_node.strip())
    landmark_samples = [int(v) for v in landmark.get("sample_indices", [])]
    overlapping_samples = sorted(set(REPLAY_SAMPLES).intersection(landmark_samples))
    same_sample_contact_evidence = len(overlapping_samples) >= 3

    old_contact_rows = reconstruction.get("contact_gated_shift_evidence", [])
    contact_gate_candidate_present = isinstance(old_contact_rows, list) and any(
        isinstance(row, dict) and row.get("contact_gate") is True for row in old_contact_rows
    )
    grounding_verified = reconstruction.get("grounding_verified") is True
    planted_contact_claimed = landmark.get("planted_contact_claimed") is True

    # A node name alone is not a canonical numeric ground plane/collider transform.
    # The old contact-gate rows also cannot authorize the replay samples because
    # their own receipt explicitly keeps grounding_verified=false, and the
    # landmark samples [114..118] do not overlap replay samples [68..71].
    canonical_ground_reference_ready = False
    contact_phase_ready = (
        source_ground_reference_present
        and same_sample_contact_evidence
        and grounding_verified
        and planted_contact_claimed
    )
    quantitative_foot_slide_candidate = False

    report = {
        "schema": "grand-bruxelles-civ1-ground-contact-reference-v1",
        "diagnostic_only": True,
        "replay_samples": REPLAY_SAMPLES,
        "fixed_vertex_count": REQUIRED_VERTEX_COUNT,
        "stable_replay_sample_count": int(replay.get("stable_replay_sample_count", 0)),
        "source_ground_node": source_ground_node,
        "source_ground_reference_present": source_ground_reference_present,
        "canonical_ground_reference_ready": canonical_ground_reference_ready,
        "landmark_samples": landmark_samples,
        "overlapping_replay_landmark_samples": overlapping_samples,
        "same_sample_contact_evidence": same_sample_contact_evidence,
        "contact_gate_candidate_present": contact_gate_candidate_present,
        "grounding_verified": grounding_verified,
        "planted_contact_claimed": planted_contact_claimed,
        "contact_phase_ready": contact_phase_ready,
        "quantitative_foot_slide_candidate": quantitative_foot_slide_candidate,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "blockers": [
            "source_ground_node_has_no_numeric_world_plane_or_collider_transform_in_consumed_evidence",
            "replay_samples_68_71_do_not_overlap_landmark_samples_114_118",
            "fixed_length_receipt_grounding_verified_is_false",
            "landmark_receipt_planted_contact_claimed_is_false",
        ],
        "next_required_evidence": "capture exact replay samples [68,69,70,71] against the real Ground support collider/plane in the loaded scene, preserving 1280x720 player-view provenance, then derive contact-relative displacement without percentile/camera/viewport rescue",
    }
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    if not source_ground_reference_present:
        print("CIV1_GROUND_CONTACT_FAIL:no-source-ground-reference", file=sys.stderr)
        return 8
    if canonical_ground_reference_ready or contact_phase_ready or quantitative_foot_slide_candidate:
        print("CIV1_GROUND_CONTACT_FAIL:unsafe-promotion", file=sys.stderr)
        return 9
    print(
        "CIV1_GROUND_CONTACT_OK",
        f"ground_node={source_ground_node}",
        f"overlap={len(overlapping_samples)}",
        f"grounding_verified={grounding_verified}",
        f"planted_contact={planted_contact_claimed}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
