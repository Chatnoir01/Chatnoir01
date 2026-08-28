#!/usr/bin/env python3
import json
import sys
from copy import deepcopy
from pathlib import Path

EXPECTED_SOURCE_ARTIFACT = 9661224043
EXPECTED_SOURCE_DIGEST = "sha256:c44b7a008e646cdcbc2b6ef41d37e9586855f45f43d73e193dec0287e3680bca"
GATES = {
    "max_transfer_error_deg": 3.0,
    "max_grounding_span_m": 0.18,
    "max_skin_edge_change_m": 0.25,
    "max_skin_stretch_ratio": 3.0,
    "min_skin_compression_ratio": 0.25,
}


def build_plan(classification, manifest):
    assert classification["state"] == "MULTIPLE_RIGHT_ARM_SKIN_BOUNDARIES_CONFIRMED"
    assert classification["source_artifact_id"] == EXPECTED_SOURCE_ARTIFACT
    assert classification["source_artifact_digest"] == EXPECTED_SOURCE_DIGEST
    assert manifest["gates"] == GATES, (manifest["gates"], GATES)
    rails = manifest["rails"]
    for key in ("production_authorized", "activation_ready", "adoption_ready", "visual_approval_claimed", "retarget_change_authorized", "skin_weight_change_authorized", "global_right_arm_fix_authorized"):
        assert rails[key] is False, key

    families = classification["families"]
    assert set(families) == {"shoulder_torso", "forearm_hand", "upperarm_clavicle"}
    assert families["shoulder_torso"]["sample"] == 10
    assert families["forearm_hand"]["sample"] == 0
    assert families["upperarm_clavicle"]["sample"] == 2

    shoulder_bones = set(manifest["families"]["shoulder_torso"]["bones"]) | set(manifest["families"]["upperarm_clavicle"]["bones"])
    hand_bones = set(manifest["families"]["forearm_hand"]["bones"])
    assert shoulder_bones == {"spine_03", "clavicle_r", "upperarm_r"}, shoulder_bones
    assert hand_bones == {"lowerarm_r", "hand_r"}, hand_bones
    assert shoulder_bones.isdisjoint(hand_bones), (shoulder_bones, hand_bones)

    return {
        "format": "grand-bruxelles-gate8-variant03-steve-boundary-ab-plan-v1",
        "state": "READY_FOR_TWO_INDEPENDENT_BOUNDARY_ABS",
        "source_artifact_id": EXPECTED_SOURCE_ARTIFACT,
        "source_artifact_digest": EXPECTED_SOURCE_DIGEST,
        "unchanged_gates": deepcopy(GATES),
        "experiments": [
            {"id":"AB_SHOULDER","samples":[2,10],"bones":sorted(shoulder_bones),"must_remeasure_records":["max_absolute_edge","min_compression_edge"],"must_not_mutate_bones":sorted(hand_bones)},
            {"id":"AB_HAND","samples":[0],"bones":sorted(hand_bones),"must_remeasure_records":["max_stretch_edge"],"must_not_mutate_bones":sorted(shoulder_bones)},
        ],
        "cross_experiment_regression_required": True,
        "global_right_arm_fix_authorized": False,
        "retarget_change_authorized": False,
        "skin_weight_change_authorized": False,
        "production_authorized": False,
        "visual_witness_authorized": False,
    }


def self_test():
    classification = {
        "state": "MULTIPLE_RIGHT_ARM_SKIN_BOUNDARIES_CONFIRMED",
        "source_artifact_id": EXPECTED_SOURCE_ARTIFACT,
        "source_artifact_digest": EXPECTED_SOURCE_DIGEST,
        "families": {"shoulder_torso":{"sample":10},"forearm_hand":{"sample":0},"upperarm_clavicle":{"sample":2}},
    }
    manifest = {
        "gates": deepcopy(GATES),
        "families": {
            "shoulder_torso": {"bones": ["spine_03", "clavicle_r", "upperarm_r"]},
            "forearm_hand": {"bones": ["lowerarm_r", "hand_r"]},
            "upperarm_clavicle": {"bones": ["spine_03", "clavicle_r", "upperarm_r"]},
        },
        "rails": {k: False for k in ("production_authorized", "activation_ready", "adoption_ready", "visual_approval_claimed", "retarget_change_authorized", "skin_weight_change_authorized", "global_right_arm_fix_authorized")},
    }
    p = build_plan(classification, manifest)
    assert [e["id"] for e in p["experiments"]] == ["AB_SHOULDER", "AB_HAND"]
    assert p["visual_witness_authorized"] is False

    bad = deepcopy(manifest)
    bad["families"]["forearm_hand"]["bones"].append("upperarm_r")
    try:
        build_plan(classification, bad)
        raise AssertionError("cross-boundary mutation was accepted")
    except AssertionError as exc:
        assert "cross-boundary mutation was accepted" not in str(exc)

    bad = deepcopy(manifest)
    bad["gates"]["max_skin_stretch_ratio"] = 4.0
    try:
        build_plan(classification, bad)
        raise AssertionError("threshold drift was accepted")
    except AssertionError as exc:
        assert "threshold drift was accepted" not in str(exc)

    print("GATE8_V03_BOUNDARY_AB_PLANNER_TESTS_OK tests=3")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test(); return
    if len(sys.argv) != 4:
        raise SystemExit("usage: plan_gate8_variant03_steve_boundary_ab.py classification.json manifest.json output.json")
    classification = json.loads(Path(sys.argv[1]).read_text())
    manifest = json.loads(Path(sys.argv[2]).read_text())
    plan = build_plan(classification, manifest)
    Path(sys.argv[3]).write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
    print("GATE8_V03_BOUNDARY_AB_PLAN_OK state=%s experiments=%d" % (plan["state"], len(plan["experiments"])))

if __name__ == "__main__":
    main()
