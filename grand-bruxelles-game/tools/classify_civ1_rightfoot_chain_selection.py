#!/usr/bin/env python3
import json
import sys
from pathlib import Path

SCHEMA_IN = "grand-bruxelles-civ1-rightfoot-chain-geometry-v5"
SCHEMA_OUT = "grand-bruxelles-civ1-rightfoot-chain-selection-v1"


def classify(receipt: dict) -> dict:
    required_false = (
        "contact_phase_ready",
        "quantitative_foot_slide_candidate",
        "animation_correction_authorized",
        "runtime_authorized",
        "visual_approval_claimed",
        "player_view_claimed",
    )
    if receipt.get("schema") != SCHEMA_IN:
        raise ValueError("unexpected source schema")
    if receipt.get("threshold_tuned") is not False:
        raise ValueError("weight threshold tuning is forbidden")
    if receipt.get("toe_is_descendant_of_rightfoot") is not True:
        raise ValueError("RightToeBase topology relation is not proven")
    if receipt.get("unresolved_positive_bind_slot_count") != 0:
        raise ValueError("unresolved Skin binds")
    if receipt.get("resolved_positive_bind_slot_count") != receipt.get("positive_weight_slot_count"):
        raise ValueError("Skin bind accounting mismatch")
    for key in required_false:
        if receipt.get(key) is not False:
            raise ValueError(f"source promotion must remain false: {key}")

    foot = int(receipt["target_rightfoot_positive_vertex_count"])
    toe = int(receipt["righttoebase_positive_vertex_count"])
    overlap = int(receipt["chain_overlap_vertex_count"])
    foot_only = int(receipt["rightfoot_only_vertex_count"])
    toe_only = int(receipt["righttoebase_only_vertex_count"])
    union = int(receipt["chain_union_vertex_count"])

    if min(foot, toe, overlap, union) <= 0:
        raise ValueError("empty fixed geometry set")
    if union != foot + toe - overlap:
        raise ValueError("union accounting mismatch")
    if union != foot_only + toe_only + overlap:
        raise ValueError("partition accounting mismatch")
    if len(receipt.get("chain_union_vertices", [])) != union:
        raise ValueError("union vertex identity list mismatch")

    # This is the measured topology result from the immutable v5 Godot witness:
    # every RightFoot-positive vertex is also RightToeBase-positive. The chain
    # union is therefore exactly the RightToeBase-positive fixed vertex set.
    strict_subset_proven = foot_only == 0 and overlap == foot and union == toe and toe_only == toe - foot
    if not strict_subset_proven:
        raise ValueError("expected measured RightFoot subset of RightToeBase was not reproduced")

    return {
        "schema": SCHEMA_OUT,
        "source_schema": SCHEMA_IN,
        "selection_basis": "measured_fixed_skin_vertex_set_relation_only",
        "selection_kind": "rightfoot_to_righttoebase_chain_union",
        "selection_equivalence": "chain_union_equals_righttoebase_positive_vertex_set",
        "selection_vertex_count": union,
        "rightfoot_vertex_count": foot,
        "righttoebase_vertex_count": toe,
        "overlap_vertex_count": overlap,
        "rightfoot_only_vertex_count": foot_only,
        "righttoebase_only_vertex_count": toe_only,
        "rightfoot_is_strict_subset_of_righttoebase": True,
        "immutable_vertex_identity_fields": ["mesh_path", "surface", "vertex"],
        "weight_cutoff_used": False,
        "raster_or_camera_heuristic_used": False,
        "next_selection_authorized": True,
        "authorized_next_use": "bone_local_contact_stability_witness_only",
        "minimum_stable_samples_required": 3,
        "contact_phase_ready": False,
        "quantitative_foot_slide_candidate": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
    }


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: classify_civ1_rightfoot_chain_selection.py INPUT.json OUTPUT.json", file=sys.stderr)
        return 2
    source = json.loads(Path(sys.argv[1]).read_text())
    out = classify(source)
    Path(sys.argv[2]).write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")
    print(
        "CIV1_RIGHTFOOT_CHAIN_SELECTION_OK",
        f"foot={out['rightfoot_vertex_count']}",
        f"toe={out['righttoebase_vertex_count']}",
        f"overlap={out['overlap_vertex_count']}",
        f"foot_only={out['rightfoot_only_vertex_count']}",
        f"toe_only={out['righttoebase_only_vertex_count']}",
        f"selection={out['selection_vertex_count']}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
