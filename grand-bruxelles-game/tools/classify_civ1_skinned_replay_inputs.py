#!/usr/bin/env python3
import json, sys
from pathlib import Path

SAMPLES = [68, 69, 70, 71]
POSE_SEMANTIC_ALIASES = {
    'RightLeg': 'RightLowerLeg',
    'LeftLeg': 'LeftLowerLeg',
}

def load_schema(root: str, schema: str):
    for p in Path(root).rglob('*.json'):
        try:
            d = json.loads(p.read_text())
        except Exception:
            continue
        if isinstance(d, dict) and d.get('schema') == schema:
            return d, p
    raise SystemExit(f'missing schema {schema} under {root}')

def short_bone(name: str) -> str:
    return name.removeprefix('mixamorig_')

def canonical_pose_semantic(name: str) -> str:
    short = short_bone(name)
    return POSE_SEMANTIC_ALIASES.get(short, short)

def main() -> int:
    if len(sys.argv) != 5:
        print('usage: classify_civ1_skinned_replay_inputs.py BASIS_DIR SKELETON_DIR TOE_DIR OUT_JSON', file=sys.stderr)
        return 2
    basis, basis_path = load_schema(sys.argv[1], 'grand-bruxelles-civ1-rightfoot-full-skin-basis-v2')
    skeleton, skeleton_path = load_schema(sys.argv[2], 'grand-bruxelles-civ1-skeleton-witness-bundle-v1')
    toe, toe_path = load_schema(sys.argv[3], 'grand-bruxelles-civ1-righttoebase-pose-v1')

    assert basis['selection_vertex_count'] == 3306
    assert basis['full_vertex_influence_basis_integrity_ready'] is True
    assert basis['normalization_violation_count'] == 0
    vertices = basis['vertices']
    assert len(vertices) == 3306
    ids = [f"{v['mesh_path']}|{v['surface']}|{v['vertex']}" for v in vertices]
    assert len(set(ids)) == 3306

    required_raw = set()
    required = set()
    for v in vertices:
        assert v['influences']
        for inf in v['influences']:
            assert float(inf['weight']) > 0.0
            raw = short_bone(str(inf['bone_name']))
            required_raw.add(raw)
            required.add(canonical_pose_semantic(raw))

    frames = skeleton['frames']
    frame_by_index = {int(f['sample_index']): f for f in frames}
    assert all(i in frame_by_index for i in SAMPLES)
    toe_samples = {int(r['sample_index']): r for r in toe['samples']}
    assert set(SAMPLES).issubset(toe_samples)
    assert toe['righttoebase_direct_child_of_rightfoot'] is True
    assert toe['pose_coverage_ready'] is True

    per_sample = []
    missing_union = set()
    for i in SAMPLES:
        poses = frame_by_index[i]['poses']
        available = {canonical_pose_semantic(k) for k in poses.keys()} | {'RightToeBase'}
        missing = sorted(required - available)
        missing_union.update(missing)
        per_sample.append({
            'sample_index': i,
            'required_influence_bones': sorted(required),
            'available_pose_bones': sorted(available),
            'missing_influence_pose_bones': missing,
            'complete': not missing,
        })

    report = {
        'schema': 'grand-bruxelles-civ1-skinned-replay-input-coverage-v1',
        'diagnostic_only': True,
        'basis_source': str(basis_path),
        'skeleton_source': str(skeleton_path),
        'righttoebase_source': str(toe_path),
        'sample_indices': SAMPLES,
        'selection_vertex_count': 3306,
        'required_raw_influence_bones': sorted(required_raw),
        'required_influence_bone_count': len(required),
        'required_influence_bones': sorted(required),
        'pose_semantic_aliases': POSE_SEMANTIC_ALIASES,
        'missing_required_pose_bones': sorted(missing_union),
        'samples': per_sample,
        'skinning_input_complete': not missing_union,
        'bone_local_witness_authorized': not missing_union,
        'contact_phase_ready': False,
        'quantitative_foot_slide_candidate': False,
        'animation_correction_authorized': False,
        'runtime_authorized': False,
        'visual_approval_claimed': False,
        'player_view_claimed': False,
    }
    Path(sys.argv[4]).write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print('CIV1_SKINNED_REPLAY_INPUT_COVERAGE_OK', 'required_raw=', sorted(required_raw), 'required=', sorted(required), 'missing=', sorted(missing_union), 'authorized=', not missing_union)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
