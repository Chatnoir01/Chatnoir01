#!/usr/bin/env python3
import json
import sys
from pathlib import Path

BASIS_SCHEMA = "grand-bruxelles-civ1-rightfoot-full-skin-basis-v2"
COVERAGE_SCHEMA = "grand-bruxelles-civ1-skinned-replay-input-coverage-v1"
OUT_SCHEMA = "grand-bruxelles-civ1-skinned-bind-space-readiness-v1"
REQUIRED_SAMPLES = [68, 69, 70, 71]


def load_schema(root: str, schema: str):
    for path in Path(root).rglob("*.json"):
        try:
            value = json.loads(path.read_text())
        except Exception:
            continue
        if isinstance(value, dict) and value.get("schema") == schema:
            return value, path
    raise SystemExit(f"missing schema {schema} under {root}")


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: classify_civ1_skinned_bind_space.py BASIS_DIR COVERAGE_DIR OUT_JSON", file=sys.stderr)
        return 2

    basis, basis_path = load_schema(sys.argv[1], BASIS_SCHEMA)
    coverage, coverage_path = load_schema(sys.argv[2], COVERAGE_SCHEMA)

    assert basis["selection_vertex_count"] == 3306
    assert basis["full_vertex_influence_basis_integrity_ready"] is True
    assert basis["normalization_violation_count"] == 0
    assert coverage["sample_indices"] == REQUIRED_SAMPLES
    assert coverage["selection_vertex_count"] == 3306
    assert coverage["missing_required_pose_bones"] == []
    assert coverage["bone_local_witness_authorized"] is True

    vertices = basis["vertices"]
    assert len(vertices) == 3306
    ids = [f"{v['mesh_path']}|{v['surface']}|{v['vertex']}" for v in vertices]
    assert len(ids) == len(set(ids)) == 3306

    # A mathematically valid linear-blend replay needs the transform that maps each
    # vertex from mesh/rest space into every influencing bone's bind space. The v2
    # basis intentionally persisted identity, source position and normalized weights,
    # but it did not persist inverse bind/rest transforms. Do not silently substitute
    # a rigid parent transform or treat global bone pose as a bind matrix.
    vertex_position_ready = all(
        isinstance(v.get("vertex_position"), list) and len(v["vertex_position"]) == 3
        for v in vertices
    )
    positive_influences_ready = all(
        v.get("influences") and all(float(i["weight"]) > 0.0 for i in v["influences"])
        for v in vertices
    )

    bind_keys = (
        "inverse_bind_transform",
        "inverse_bind_matrix",
        "bind_transform",
        "bone_global_rest",
        "mesh_to_skeleton_rest",
    )
    vertices_with_bind_space = 0
    influence_slots = 0
    influence_slots_with_bind_space = 0
    for v in vertices:
        vertex_has_all = True
        for inf in v["influences"]:
            influence_slots += 1
            has_bind = any(key in inf for key in bind_keys)
            if has_bind:
                influence_slots_with_bind_space += 1
            else:
                vertex_has_all = False
        if vertex_has_all:
            vertices_with_bind_space += 1

    bind_space_complete = (
        vertices_with_bind_space == 3306
        and influence_slots_with_bind_space == influence_slots
    )

    report = {
        "schema": OUT_SCHEMA,
        "diagnostic_only": True,
        "basis_source": str(basis_path),
        "coverage_source": str(coverage_path),
        "sample_indices": REQUIRED_SAMPLES,
        "selection_vertex_count": 3306,
        "vertex_position_ready": vertex_position_ready,
        "positive_influences_ready": positive_influences_ready,
        "pose_coverage_ready": True,
        "vertices_with_complete_bind_space": vertices_with_bind_space,
        "positive_influence_slot_count": influence_slots,
        "positive_influence_slots_with_bind_space": influence_slots_with_bind_space,
        "bind_space_complete": bind_space_complete,
        "rigid_parent_proxy_authorized": False,
        "global_pose_as_bind_matrix_authorized": False,
        "skinned_replay_authorized": bind_space_complete,
        "contact_phase_ready": False,
        "quantitative_foot_slide_candidate": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "next_required_evidence": (
            "persist exact Godot Skin bind/rest mapping for every positive influence "
            "of the same 3306 immutable mesh_path/surface/vertex IDs"
            if not bind_space_complete else "none"
        ),
    }
    Path(sys.argv[3]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(
        "CIV1_SKINNED_BIND_SPACE_READINESS_OK",
        f"vertices={vertices_with_bind_space}/3306",
        f"slots={influence_slots_with_bind_space}/{influence_slots}",
        f"authorized={bind_space_complete}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
