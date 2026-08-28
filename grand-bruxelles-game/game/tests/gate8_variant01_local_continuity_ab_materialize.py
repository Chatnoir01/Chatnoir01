from __future__ import annotations

import collections
import json
import pathlib
import sys

if len(sys.argv) != 5:
    raise SystemExit("usage: materialize.py SOURCE_GD TOPOLOGY_RESULT OUT_BASELINE_GD OUT_CANDIDATE_GD")

source_path = pathlib.Path(sys.argv[1])
topology_path = pathlib.Path(sys.argv[2])
baseline_path = pathlib.Path(sys.argv[3])
candidate_path = pathlib.Path(sys.argv[4])
text = source_path.read_text()

required = [
    'const TARGET_SCENE := "res://assets/npc_gate_06.glb"',
    'const OUTPUT_PATH := "res://gate8_variant06_target_micropose_skin_result.json"',
    'const EXPECTED_VERTICES := 24073',
    'const MICROPOSE_DEG := 5.0',
    'const MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25',
    'const MAX_EDGE_STRETCH_RATIO := 3.0',
    'const MIN_EDGE_COMPRESSION_RATIO := 0.25',
    'posed[vi] = common_inverse * _skin_vertex(skin, vv[vi], bb, ww, vi, n)',
    'result[_surface_key(mi, s)] = posed',
    'func _skin_vertex(skin: Skin, vertex: Vector3, bones, weights, vi: int, n: int) -> Vector3:',
    '"candidate_variant":6',
]
for token in required:
    if token not in text:
        raise SystemExit(f"validated harness drift: missing {token!r}")

# Materialize an exact variant01 baseline from the already validated target-only harness.
baseline = text.replace('res://assets/npc_gate_06.glb', 'res://assets/npc_gate_01.glb')
baseline = baseline.replace('res://gate8_variant06_target_micropose_skin_result.json', 'res://baseline-result.json')
baseline = baseline.replace('EXPECTED_VERTICES := 24073', 'EXPECTED_VERTICES := 21044')
baseline = baseline.replace('"candidate_variant":6', '"candidate_variant":1')
baseline = baseline.replace('grand-bruxelles-gate8-variant06-target-micropose-skin-v1', 'grand-bruxelles-gate8-variant01-local-continuity-baseline-v1')
baseline = baseline.replace('REJECT_VARIANT06_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED', 'LOCAL_CONTINUITY_AB_BASELINE')

# Consume only topology-proven discontinuity witnesses from the immutable #1443 artifact.
topology = json.loads(topology_path.read_text())
if topology.get('diagnostic_state') != 'INFLUENCE_TOPOLOGY_DIAGNOSED':
    raise SystemExit('topology diagnostic state mismatch')
rows = topology.get('blocked_case_topology', [])
if len(rows) != 48:
    raise SystemExit(f'expected 48 blocked topology rows, got {len(rows)}')
accepted = {'rotated_bone_weight_discontinuity', 'rotated_bone_one_sided'}
selected = [r for r in rows if r.get('topology', {}).get('classification') in accepted]
if len(selected) != 36:
    raise SystemExit(f'expected 36 direct discontinuity witnesses, got {len(selected)}')

original: dict[tuple[str, int], dict[str, float]] = {}
proposals: dict[tuple[str, int, str], list[float]] = collections.defaultdict(list)

for row in selected:
    surface = str(row['surface'])
    topo = row['topology']
    pivot = str(topo['rotated_bone'])
    wa = float(topo['rotated_weight_a'])
    wb = float(topo['rotated_weight_b'])
    target = (wa + wb) * 0.5
    for suffix in ('a', 'b'):
        vertex = int(row[f'vertex_{suffix}'])
        infs = topo[f'vertex_{suffix}_influences']
        key = (surface, vertex)
        weights = {str(i['bone']): float(i['weight']) for i in infs}
        if abs(sum(weights.values()) - 1.0) > 0.001:
            raise SystemExit(f'non-normalized observed vertex {key}')
        if key in original:
            prior = original[key]
            names = set(prior) | set(weights)
            if any(abs(prior.get(n, 0.0) - weights.get(n, 0.0)) > 1e-5 for n in names):
                raise SystemExit(f'inconsistent original weights for {key}')
        else:
            original[key] = weights
        proposals[(surface, vertex, pivot)].append(target)

candidate_vectors: dict[str, dict[str, float]] = {}
for (surface, vertex), base in sorted(original.items()):
    updated = dict(base)
    touched = False
    for (s, v, bone), vals in proposals.items():
        if s == surface and v == vertex:
            updated[bone] = sum(vals) / len(vals)
            touched = True
    if not touched:
        continue
    total = sum(updated.values())
    if total <= 1e-9:
        raise SystemExit(f'zero candidate weight sum for {(surface, vertex)}')
    updated = {bone: weight / total for bone, weight in updated.items() if weight > 1e-9}
    if abs(sum(updated.values()) - 1.0) > 1e-6:
        raise SystemExit(f'candidate normalization failed for {(surface, vertex)}')
    candidate_vectors[f'{surface}|{vertex}'] = updated

if not candidate_vectors:
    raise SystemExit('no local candidate vertices materialized')

candidate = baseline.replace('res://baseline-result.json', 'res://candidate-result.json')
candidate = candidate.replace('grand-bruxelles-gate8-variant01-local-continuity-baseline-v1', 'grand-bruxelles-gate8-variant01-local-continuity-candidate-v1')
candidate = candidate.replace('LOCAL_CONTINUITY_AB_BASELINE', 'LOCAL_CONTINUITY_AB_CANDIDATE')

marker = 'const COMMON_ROTATION_EPS_DEG := 0.01\n'
if marker not in candidate:
    raise SystemExit('constant insertion marker missing')
map_literal = json.dumps(candidate_vectors, sort_keys=True, separators=(',', ':'))
candidate = candidate.replace(
    marker,
    marker + f'const LOCAL_CONTINUITY_WEIGHTS := {map_literal}\n',
    1,
)

candidate = candidate.replace(
    'var n := int(bb.size() / vv.size())\n            var posed := PackedVector3Array()',
    'var n := int(bb.size() / vv.size())\n            var surface_key := _surface_key(mi, s)\n            var posed := PackedVector3Array()',
    1,
)
candidate = candidate.replace(
    'posed[vi] = common_inverse * _skin_vertex(skin, vv[vi], bb, ww, vi, n)',
    'posed[vi] = common_inverse * _skin_vertex_local_continuity(surface_key, skin, vv[vi], bb, ww, vi, n)',
    1,
)
candidate = candidate.replace('result[_surface_key(mi, s)] = posed', 'result[surface_key] = posed', 1)

insert_before = 'func _skin_vertex(skin: Skin, vertex: Vector3, bones, weights, vi: int, n: int) -> Vector3:\n'
helper = r'''func _skin_vertex_local_continuity(surface_key: String, skin: Skin, vertex: Vector3, bones, weights, vi: int, n: int) -> Vector3:
    var correction_key := "%s|%d" % [surface_key, vi]
    if not LOCAL_CONTINUITY_WEIGHTS.has(correction_key):
        return _skin_vertex(skin, vertex, bones, weights, vi, n)
    var corrected: Dictionary = LOCAL_CONTINUITY_WEIGHTS[correction_key]
    var out := Vector3.ZERO
    var total := 0.0
    for bone_name_value in corrected.keys():
        var bone_name := String(bone_name_value)
        var weight := float(corrected[bone_name_value])
        if weight <= 0.0:
            continue
        var bone_idx := target.find_bone(bone_name)
        if bone_idx < 0:
            failures.append("local_continuity_bone_missing=%s" % bone_name)
            continue
        var bind_idx := _find_skin_bind_for_bone(skin, bone_idx)
        if bind_idx < 0:
            failures.append("local_continuity_bind_missing=%s" % bone_name)
            continue
        out += (target.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_idx) * vertex) * weight
        total += weight
    if total <= 0.000001:
        failures.append("local_continuity_zero_weight=%s" % correction_key)
        return _skin_vertex(skin, vertex, bones, weights, vi, n)
    return out / total

func _find_skin_bind_for_bone(skin: Skin, bone_idx: int) -> int:
    for bind_idx in range(skin.get_bind_count()):
        if _resolve_skin_bone(skin, bind_idx) == bone_idx:
            return bind_idx
    return -1

'''
if insert_before not in candidate:
    raise SystemExit('skin function insertion marker missing')
candidate = candidate.replace(insert_before, helper + insert_before, 1)

meta_marker = '        "measurement":"target_only_controlled_micropose_cpu_skin_space",\n'
if meta_marker not in candidate:
    raise SystemExit('metadata marker missing')
candidate = candidate.replace(
    meta_marker,
    meta_marker + '        "local_continuity_candidate":true,\n        "canonical_glb_modified":false,\n        "candidate_corrected_vertex_count":LOCAL_CONTINUITY_WEIGHTS.size(),\n',
    1,
)

for frozen in ('MICROPOSE_DEG := 5.0', 'MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25', 'MAX_EDGE_STRETCH_RATIO := 3.0', 'MIN_EDGE_COMPRESSION_RATIO := 0.25'):
    if frozen not in baseline or frozen not in candidate:
        raise SystemExit(f'frozen rail drift: {frozen}')
if 'RetargetModifier3D' in baseline or 'RetargetModifier3D' in candidate:
    raise SystemExit('retarget rail violated')

baseline_path.write_text(baseline)
candidate_path.write_text(candidate)
print(json.dumps({
    'selected_discontinuity_cases': len(selected),
    'corrected_vertex_count': len(candidate_vectors),
    'corrected_vertex_bone_pairs': len(proposals),
}, sort_keys=True))
