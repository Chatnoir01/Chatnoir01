from __future__ import annotations

import json
import pathlib
import sys

if len(sys.argv) != 6:
    raise SystemExit("usage: materialize.py SOURCE_GD CONTRACT_JSON ONE_RING_RESULT OUT_BASELINE_GD OUT_CANDIDATE_GD")

source_path = pathlib.Path(sys.argv[1])
contract = json.loads(pathlib.Path(sys.argv[2]).read_text())
one_ring = json.loads(pathlib.Path(sys.argv[3]).read_text())
baseline_path = pathlib.Path(sys.argv[4])
candidate_path = pathlib.Path(sys.argv[5])
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
baseline = baseline.replace('grand-bruxelles-gate8-variant06-target-micropose-skin-v1', 'grand-bruxelles-gate8-variant01-shoulder-consensus-baseline-v1')
baseline = baseline.replace('REJECT_VARIANT06_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED', 'SHOULDER_CONSENSUS_AB_BASELINE')

if one_ring.get('diagnostic_state') != contract['one_ring']['expected_state']:
    raise SystemExit('one-ring diagnostic state mismatch')
if int(one_ring.get('audited_edge_count', -1)) != int(contract['one_ring']['expected_edges']):
    raise SystemExit('one-ring edge count mismatch')
if one_ring.get('failures') != []:
    raise SystemExit('one-ring source contains failures')

op = contract['operator']
shoulders = [e for e in one_ring.get('edges', []) if e.get('family') == op['family']]
if len(shoulders) != int(op['expected_edges']):
    raise SystemExit(f"expected {op['expected_edges']} shoulder edges, got {len(shoulders)}")


def influence_map(report: dict) -> dict[str, float]:
    out: dict[str, float] = {}
    for row in report.get('influences', []):
        name = str(row.get('bone', ''))
        if not name:
            raise SystemExit('missing bone name in one-ring evidence')
        out[name] = out.get(name, 0.0) + float(row['weight'])
    if abs(sum(out.values()) - 1.0) > 0.001:
        raise SystemExit(f'non-normalized evidence weights: {sum(out.values())}')
    return out


def average_maps(maps: list[dict[str, float]]) -> dict[str, float]:
    if not maps:
        raise SystemExit('empty consensus maps')
    keys = sorted({k for m in maps for k in m})
    result = {k: sum(m.get(k, 0.0) for m in maps) / len(maps) for k in keys}
    result = {k: v for k, v in result.items() if v > 1e-9}
    total = sum(result.values())
    if total <= 1e-9:
        raise SystemExit('zero consensus sum')
    result = {k: v / total for k, v in result.items()}
    if abs(sum(result.values()) - 1.0) > 1e-6:
        raise SystemExit('consensus normalization failed')
    return result

candidate_vectors: dict[str, dict[str, float]] = {}
operator_report: list[dict] = []
for edge in shoulders:
    a = edge['endpoint_a']
    b = edge['endpoint_b']
    a_other = float(a['max_other_neighbor_weight_l1'])
    b_other = float(b['max_other_neighbor_weight_l1'])
    coherent = None
    broad = None
    if a_other <= float(op['coherent_side_max_other_l1_max']) and b_other >= float(op['broad_side_max_other_l1_min']):
        coherent, broad = a, b
    elif b_other <= float(op['coherent_side_max_other_l1_max']) and a_other >= float(op['broad_side_max_other_l1_min']):
        coherent, broad = b, a
    else:
        raise SystemExit(f"shoulder family signature drift: {edge.get('vertex_a')}:{edge.get('vertex_b')} a={a_other} b={b_other}")

    consensus_maps = [influence_map(coherent)]
    accepted_neighbors = []
    for n in coherent.get('neighbors', []):
        if bool(n.get('is_worst_pair_endpoint')):
            continue
        if float(n.get('weight_l1', 999.0)) <= float(op['consensus_neighbor_l1_max']):
            consensus_maps.append(influence_map(n))
            accepted_neighbors.append(int(n['vertex']))
    if len(consensus_maps) < 2:
        raise SystemExit(f"no coherent neighbor consensus for shoulder edge {edge.get('vertex_a')}:{edge.get('vertex_b')}")

    surface = str(edge['surface'])
    broad_vertex = int(broad['vertex'])
    key = f'{surface}|{broad_vertex}'
    if key in candidate_vectors:
        raise SystemExit(f'duplicate corrected vertex {key}')
    candidate_vectors[key] = average_maps(consensus_maps)
    operator_report.append({
        'surface': surface,
        'edge': [int(edge['vertex_a']), int(edge['vertex_b'])],
        'coherent_vertex': int(coherent['vertex']),
        'broad_vertex': broad_vertex,
        'coherent_max_other_l1': float(coherent['max_other_neighbor_weight_l1']),
        'broad_max_other_l1': float(broad['max_other_neighbor_weight_l1']),
        'accepted_consensus_neighbors': accepted_neighbors,
        'consensus_member_count': len(consensus_maps),
        'replacement_weights': candidate_vectors[key],
    })

if len(candidate_vectors) != int(op['expected_corrected_vertices']):
    raise SystemExit(f"expected {op['expected_corrected_vertices']} corrected vertices, got {len(candidate_vectors)}")

candidate = baseline.replace('res://baseline-result.json', 'res://candidate-result.json')
candidate = candidate.replace('grand-bruxelles-gate8-variant01-shoulder-consensus-baseline-v1', 'grand-bruxelles-gate8-variant01-shoulder-consensus-candidate-v1')
candidate = candidate.replace('SHOULDER_CONSENSUS_AB_BASELINE', 'SHOULDER_CONSENSUS_AB_CANDIDATE')
marker = 'const COMMON_ROTATION_EPS_DEG := 0.01\n'
if marker not in candidate:
    raise SystemExit('constant insertion marker missing')
map_literal = json.dumps(candidate_vectors, sort_keys=True, separators=(',', ':'))
candidate = candidate.replace(marker, marker + f'const SHOULDER_CONSENSUS_WEIGHTS := {map_literal}\n', 1)
candidate = candidate.replace(
    'var n := int(bb.size() / vv.size())\n            var posed := PackedVector3Array()',
    'var n := int(bb.size() / vv.size())\n            var surface_key := _surface_key(mi, s)\n            var posed := PackedVector3Array()',
    1,
)
candidate = candidate.replace(
    'posed[vi] = common_inverse * _skin_vertex(skin, vv[vi], bb, ww, vi, n)',
    'posed[vi] = common_inverse * _skin_vertex_shoulder_consensus(surface_key, skin, vv[vi], bb, ww, vi, n)',
    1,
)
candidate = candidate.replace('result[_surface_key(mi, s)] = posed', 'result[surface_key] = posed', 1)
insert_before = 'func _skin_vertex(skin: Skin, vertex: Vector3, bones, weights, vi: int, n: int) -> Vector3:\n'
helper = r'''func _skin_vertex_shoulder_consensus(surface_key: String, skin: Skin, vertex: Vector3, bones, weights, vi: int, n: int) -> Vector3:
    var correction_key := "%s|%d" % [surface_key, vi]
    if not SHOULDER_CONSENSUS_WEIGHTS.has(correction_key):
        return _skin_vertex(skin, vertex, bones, weights, vi, n)
    var corrected: Dictionary = SHOULDER_CONSENSUS_WEIGHTS[correction_key]
    var out := Vector3.ZERO
    var total := 0.0
    for bone_name_value in corrected.keys():
        var bone_name := String(bone_name_value)
        var weight := float(corrected[bone_name_value])
        if weight <= 0.0:
            continue
        var bone_idx := target.find_bone(bone_name)
        if bone_idx < 0:
            failures.append("shoulder_consensus_bone_missing=%s" % bone_name)
            continue
        var bind_idx := _find_skin_bind_for_bone(skin, bone_idx)
        if bind_idx < 0:
            failures.append("shoulder_consensus_bind_missing=%s" % bone_name)
            continue
        out += (target.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_idx) * vertex) * weight
        total += weight
    if total <= 0.000001:
        failures.append("shoulder_consensus_zero_weight=%s" % correction_key)
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
    meta_marker + '        "shoulder_consensus_candidate":true,\n        "canonical_glb_modified":false,\n        "candidate_corrected_vertex_count":SHOULDER_CONSENSUS_WEIGHTS.size(),\n',
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
    'operator': 'shoulder_coherent_one_ring_consensus',
    'corrected_vertex_count': len(candidate_vectors),
    'shoulder_edges': operator_report,
}, indent=2, sort_keys=True))
