from __future__ import annotations

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

baseline = text.replace('res://assets/npc_gate_06.glb', 'res://assets/npc_gate_01.glb')
baseline = baseline.replace('res://gate8_variant06_target_micropose_skin_result.json', 'res://baseline-result.json')
baseline = baseline.replace('EXPECTED_VERTICES := 24073', 'EXPECTED_VERTICES := 21044')
baseline = baseline.replace('"candidate_variant":6', '"candidate_variant":1')
baseline = baseline.replace('grand-bruxelles-gate8-variant06-target-micropose-skin-v1', 'grand-bruxelles-gate8-variant01-hand-seam-baseline-v1')
baseline = baseline.replace('REJECT_VARIANT06_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED', 'HAND_SEAM_FULL_VECTOR_AB_BASELINE')

topology = json.loads(topology_path.read_text())
if topology.get('diagnostic_state') != 'INFLUENCE_TOPOLOGY_DIAGNOSED':
    raise SystemExit('topology diagnostic state mismatch')
rows = topology.get('blocked_case_topology', [])
shared = [r for r in rows if r.get('topology', {}).get('classification') == 'shared_influences']
if len(shared) != 12:
    raise SystemExit(f'expected 12 shared-influence witnesses, got {len(shared)}')

edge_rows: dict[tuple[str, int, int], list[dict]] = {}
for row in shared:
    key = (str(row['surface']), int(row['vertex_a']), int(row['vertex_b']))
    edge_rows.setdefault(key, []).append(row)
if len(edge_rows) != 2:
    raise SystemExit(f'expected exactly two unique shared seams, got {len(edge_rows)}')
if any(len(v) != 6 for v in edge_rows.values()):
    raise SystemExit('each unique shared seam must account for six XYZ +/- witnesses')

candidate_vectors: dict[str, dict[str, float]] = {}
edge_summary = []
for (surface, va, vb), group in sorted(edge_rows.items()):
    first = group[0]['topology']
    def vec(which: str) -> dict[str, float]:
        return {str(i['bone']): float(i['weight']) for i in first[f'vertex_{which}_influences']}
    a = vec('a')
    b = vec('b')
    # Repeated witnesses must report the same endpoint distributions.
    for row in group[1:]:
        ta = {str(i['bone']): float(i['weight']) for i in row['topology']['vertex_a_influences']}
        tb = {str(i['bone']): float(i['weight']) for i in row['topology']['vertex_b_influences']}
        names = set(a) | set(ta)
        if any(abs(a.get(n, 0.0) - ta.get(n, 0.0)) > 1e-5 for n in names):
            raise SystemExit(f'inconsistent vertex A weights for {(surface,va,vb)}')
        names = set(b) | set(tb)
        if any(abs(b.get(n, 0.0) - tb.get(n, 0.0)) > 1e-5 for n in names):
            raise SystemExit(f'inconsistent vertex B weights for {(surface,va,vb)}')
    if abs(sum(a.values()) - 1.0) > 0.001 or abs(sum(b.values()) - 1.0) > 0.001:
        raise SystemExit(f'non-normalized seam endpoints {(surface,va,vb)}')
    bones = sorted(set(a) | set(b))
    mean = {bone: (a.get(bone, 0.0) + b.get(bone, 0.0)) * 0.5 for bone in bones}
    total = sum(mean.values())
    if total <= 1e-9:
        raise SystemExit('zero mean vector')
    mean = {bone: w / total for bone, w in mean.items() if w > 1e-9}
    candidate_vectors[f'{surface}|{va}'] = mean
    candidate_vectors[f'{surface}|{vb}'] = mean
    edge_summary.append({'surface':surface,'vertex_a':va,'vertex_b':vb,'bones':bones,'mean':mean})

if len(candidate_vectors) != 4:
    raise SystemExit(f'expected four corrected seam vertices, got {len(candidate_vectors)}')

candidate = baseline.replace('res://baseline-result.json', 'res://candidate-result.json')
candidate = candidate.replace('grand-bruxelles-gate8-variant01-hand-seam-baseline-v1', 'grand-bruxelles-gate8-variant01-hand-seam-candidate-v1')
candidate = candidate.replace('HAND_SEAM_FULL_VECTOR_AB_BASELINE', 'HAND_SEAM_FULL_VECTOR_AB_CANDIDATE')

marker = 'const COMMON_ROTATION_EPS_DEG := 0.01\n'
if marker not in candidate:
    raise SystemExit('constant insertion marker missing')
map_literal = json.dumps(candidate_vectors, sort_keys=True, separators=(',', ':'))
candidate = candidate.replace(marker, marker + f'const HAND_SEAM_FULL_VECTOR_WEIGHTS := {map_literal}\n', 1)

candidate = candidate.replace(
    'var n := int(bb.size() / vv.size())\n            var posed := PackedVector3Array()',
    'var n := int(bb.size() / vv.size())\n            var surface_key := _surface_key(mi, s)\n            var posed := PackedVector3Array()', 1)
candidate = candidate.replace(
    'posed[vi] = common_inverse * _skin_vertex(skin, vv[vi], bb, ww, vi, n)',
    'posed[vi] = common_inverse * _skin_vertex_hand_seam(surface_key, skin, vv[vi], bb, ww, vi, n)', 1)
candidate = candidate.replace('result[_surface_key(mi, s)] = posed', 'result[surface_key] = posed', 1)

insert_before = 'func _skin_vertex(skin: Skin, vertex: Vector3, bones, weights, vi: int, n: int) -> Vector3:\n'
helper = r'''func _skin_vertex_hand_seam(surface_key: String, skin: Skin, vertex: Vector3, bones, weights, vi: int, n: int) -> Vector3:
    var correction_key := "%s|%d" % [surface_key, vi]
    if not HAND_SEAM_FULL_VECTOR_WEIGHTS.has(correction_key):
        return _skin_vertex(skin, vertex, bones, weights, vi, n)
    var corrected: Dictionary = HAND_SEAM_FULL_VECTOR_WEIGHTS[correction_key]
    var out := Vector3.ZERO
    var total := 0.0
    for bone_name_value in corrected.keys():
        var bone_name := String(bone_name_value)
        var weight := float(corrected[bone_name_value])
        if weight <= 0.0:
            continue
        var bone_idx := target.find_bone(bone_name)
        if bone_idx < 0:
            failures.append("hand_seam_bone_missing=%s" % bone_name)
            continue
        var bind_idx := _find_skin_bind_for_bone_hand_seam(skin, bone_idx)
        if bind_idx < 0:
            failures.append("hand_seam_bind_missing=%s" % bone_name)
            continue
        out += (target.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_idx) * vertex) * weight
        total += weight
    if total <= 0.000001:
        failures.append("hand_seam_zero_weight=%s" % correction_key)
        return _skin_vertex(skin, vertex, bones, weights, vi, n)
    return out / total

func _find_skin_bind_for_bone_hand_seam(skin: Skin, bone_idx: int) -> int:
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
candidate = candidate.replace(meta_marker, meta_marker + '        "hand_seam_full_vector_candidate":true,\n        "canonical_glb_modified":false,\n        "candidate_corrected_vertex_count":HAND_SEAM_FULL_VECTOR_WEIGHTS.size(),\n', 1)

for frozen in ('MICROPOSE_DEG := 5.0','MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25','MAX_EDGE_STRETCH_RATIO := 3.0','MIN_EDGE_COMPRESSION_RATIO := 0.25'):
    if frozen not in baseline or frozen not in candidate:
        raise SystemExit(f'frozen rail drift: {frozen}')
if 'RetargetModifier3D' in baseline or 'RetargetModifier3D' in candidate:
    raise SystemExit('retarget rail violated')

baseline_path.write_text(baseline)
candidate_path.write_text(candidate)
print(json.dumps({'shared_case_count':len(shared),'unique_edges':len(edge_rows),'corrected_vertex_count':len(candidate_vectors),'edges':edge_summary},sort_keys=True))
