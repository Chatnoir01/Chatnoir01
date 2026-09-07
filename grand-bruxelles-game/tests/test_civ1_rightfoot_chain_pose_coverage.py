import importlib.util
from pathlib import Path

ROOT = Path(__file__).parents[1]
TOOL = ROOT / "tools" / "classify_civ1_rightfoot_chain_pose_coverage.py"
spec = importlib.util.spec_from_file_location("coverage", TOOL)
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)

vertices = [
    {
        "mesh_path": "/root/civ1_body/Skeleton3D/mesh",
        "surface": 0,
        "vertex": i,
        "rightfoot_weight": 0.2,
        "righttoebase_weight": 0.8,
    }
    for i in range(3306)
]
geometry = {
    "schema": "grand-bruxelles-civ1-rightfoot-chain-geometry-v5",
    "threshold_tuned": False,
    "toe_is_descendant_of_rightfoot": True,
    "unresolved_positive_bind_slot_count": 0,
    "target_bone": "mixamorig_RightFoot",
    "toe_bone": "mixamorig_RightToeBase",
    "chain_union_vertex_count": 3306,
    "rightfoot_only_vertex_count": 0,
    "chain_union_vertices": vertices,
}
frames = []
for i in range(120):
    frames.append({
        "sample_index": i,
        "poses": {
            "Hips": {}, "RightUpperLeg": {}, "RightLowerLeg": {}, "RightFoot": {},
            "LeftUpperLeg": {}, "LeftLowerLeg": {}, "LeftFoot": {},
        },
    })
bundle = {
    "schema": "grand-bruxelles-civ1-skeleton-witness-bundle-v1",
    "diagnostic_only": True,
    "runtime_authorized": False,
    "visual_approval_claimed": False,
    "player_view_claimed": False,
    "frames": frames,
}

out = coverage.classify(geometry, bundle)
assert out["selection_vertex_count"] == 3306
assert out["missing_required_chain_pose_semantics"] == ["RightToeBase"]
assert out["pose_coverage_ready"] is False
assert out["full_vertex_influence_basis_available"] is False
assert out["skinning_input_complete"] is False
assert out["rigid_parent_proxy_authorized"] is False
assert out["bone_local_witness_authorized"] is False
for key in (
    "contact_phase_ready", "quantitative_foot_slide_candidate",
    "animation_correction_authorized", "runtime_authorized",
    "visual_approval_claimed", "player_view_claimed",
):
    assert out[key] is False

complete_bundle = dict(bundle)
complete_frames = []
for frame in frames:
    f = dict(frame)
    poses = dict(frame["poses"])
    poses["RightToeBase"] = {}
    f["poses"] = poses
    complete_frames.append(f)
complete_bundle["frames"] = complete_frames
out2 = coverage.classify(geometry, complete_bundle)
assert out2["pose_coverage_ready"] is True
assert out2["full_vertex_influence_basis_available"] is False
assert out2["skinning_input_complete"] is False
assert out2["bone_local_witness_authorized"] is False

for mutation in (
    {"threshold_tuned": True},
    {"unresolved_positive_bind_slot_count": 1},
    {"chain_union_vertex_count": 3305},
    {"rightfoot_only_vertex_count": 1},
):
    bad = dict(geometry)
    bad.update(mutation)
    try:
        coverage.classify(bad, bundle)
    except ValueError:
        pass
    else:
        raise AssertionError(f"fail-open geometry mutation escaped: {mutation}")

dup = dict(geometry)
dup["chain_union_vertices"] = vertices[:-1] + [dict(vertices[0])]
try:
    coverage.classify(dup, bundle)
except ValueError:
    pass
else:
    raise AssertionError("duplicate immutable ID escaped")

source = TOOL.read_text()
for forbidden in ("camera_position", "camera_fov", "bottom_percent", "near_white", "WEIGHT_THRESHOLD"):
    assert forbidden not in source, forbidden
assert '"rigid_parent_proxy_authorized": False' in source
assert '"bone_local_witness_authorized": False' in source
print("CIV1_RIGHTFOOT_CHAIN_POSE_COVERAGE_CONTRACT_OK")
