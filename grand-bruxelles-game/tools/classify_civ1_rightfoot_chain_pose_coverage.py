#!/usr/bin/env python3
import hashlib
import json
import sys
from pathlib import Path

GEOM_SCHEMA = "grand-bruxelles-civ1-rightfoot-chain-geometry-v5"
BUNDLE_SCHEMA = "grand-bruxelles-civ1-skeleton-witness-bundle-v1"
OUT_SCHEMA = "grand-bruxelles-civ1-rightfoot-chain-pose-coverage-v1"
SAMPLES = [68, 69, 70, 71]
REQUIRED_CHAIN_POSES = ["RightFoot", "RightToeBase"]


def _fixed_id(v: dict) -> str:
    return f"{v['mesh_path']}|{int(v['surface'])}|{int(v['vertex'])}"


def classify(geometry: dict, bundle: dict) -> dict:
    if geometry.get("schema") != GEOM_SCHEMA:
        raise ValueError("unexpected geometry schema")
    if bundle.get("schema") != BUNDLE_SCHEMA:
        raise ValueError("unexpected pose bundle schema")
    if geometry.get("threshold_tuned") is not False:
        raise ValueError("threshold tuning is forbidden")
    if geometry.get("toe_is_descendant_of_rightfoot") is not True:
        raise ValueError("RightToeBase topology relation is not proven")
    if geometry.get("unresolved_positive_bind_slot_count") != 0:
        raise ValueError("unresolved Skin binds")
    if geometry.get("target_bone") != "mixamorig_RightFoot":
        raise ValueError("unexpected target bone")
    if geometry.get("toe_bone") != "mixamorig_RightToeBase":
        raise ValueError("unexpected toe bone")
    if int(geometry.get("chain_union_vertex_count", -1)) != 3306:
        raise ValueError("fixed chain count drift")
    if int(geometry.get("rightfoot_only_vertex_count", -1)) != 0:
        raise ValueError("RightFoot is no longer a subset of RightToeBase")

    vertices = geometry.get("chain_union_vertices")
    if not isinstance(vertices, list) or len(vertices) != 3306:
        raise ValueError("fixed chain vertex payload drift")
    ids = [_fixed_id(v) for v in vertices]
    if len(set(ids)) != len(ids):
        raise ValueError("duplicate immutable vertex IDs")
    fixed_id_digest = hashlib.sha256("\n".join(sorted(ids)).encode()).hexdigest()

    frames = bundle.get("frames")
    if not isinstance(frames, list) or len(frames) != 120:
        raise ValueError("pose bundle frame count drift")
    if bundle.get("diagnostic_only") is not True:
        raise ValueError("pose bundle must remain diagnostic-only")
    for key in ("runtime_authorized", "visual_approval_claimed", "player_view_claimed"):
        if bundle.get(key) is not False:
            raise ValueError(f"upstream bundle promotion is forbidden: {key}")

    available_per_sample = []
    common = None
    for sample in SAMPLES:
        frame = frames[sample]
        if int(frame.get("sample_index", -1)) != sample:
            raise ValueError(f"sample index drift at {sample}")
        poses = frame.get("poses")
        if not isinstance(poses, dict):
            raise ValueError(f"missing poses at {sample}")
        keys = set(poses.keys())
        available_per_sample.append(sorted(keys))
        common = keys if common is None else common & keys
    common = common or set()
    missing_required = [name for name in REQUIRED_CHAIN_POSES if name not in common]

    # Geometry v5 preserves target/toe aggregate weights and immutable IDs, but not
    # the complete positive bind/weight vector for every selected vertex. Without
    # that basis, correct CPU skinning cannot be reconstructed fail-closed.
    full_vertex_influence_basis_available = False
    pose_coverage_ready = not missing_required
    skinning_input_complete = pose_coverage_ready and full_vertex_influence_basis_available

    return {
        "schema": OUT_SCHEMA,
        "diagnostic_only": True,
        "samples": SAMPLES,
        "selection_vertex_count": len(ids),
        "fixed_vertex_id_sha256": fixed_id_digest,
        "required_chain_pose_semantics": REQUIRED_CHAIN_POSES,
        "common_pose_semantics": sorted(common),
        "missing_required_chain_pose_semantics": missing_required,
        "pose_coverage_ready": pose_coverage_ready,
        "full_vertex_influence_basis_available": full_vertex_influence_basis_available,
        "skinning_input_complete": skinning_input_complete,
        "rigid_parent_proxy_authorized": False,
        "bone_local_witness_authorized": False,
        "contact_phase_ready": False,
        "quantitative_foot_slide_candidate": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": (
            "AMELIORER_EXPAND_POSE_AND_PER_VERTEX_SKIN_BASIS_BEFORE_FIXED_CHAIN_WITNESS"
            if not skinning_input_complete else
            "AMELIORER_FIXED_CHAIN_SKINNING_INPUT_COMPLETE_NO_CONTACT_PROMOTION"
        ),
    }


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: classify_civ1_rightfoot_chain_pose_coverage.py GEOMETRY_JSON BUNDLE_JSON OUT_JSON", file=sys.stderr)
        return 2
    geometry = json.loads(Path(sys.argv[1]).read_text())
    bundle = json.loads(Path(sys.argv[2]).read_text())
    out = classify(geometry, bundle)
    Path(sys.argv[3]).write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")
    print("CIV1_RIGHTFOOT_CHAIN_POSE_COVERAGE_OK")
    print(json.dumps(out, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
