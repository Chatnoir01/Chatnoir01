from __future__ import annotations

import json
import pathlib
import sys

if len(sys.argv) != 8:
    raise SystemExit("usage: materialize.py SOURCE_GD CONTRACT ONE_RING TWO_RING OUT_BASELINE OUT_LEFT OUT_RIGHT")

source = pathlib.Path(sys.argv[1]).read_text()
contract = json.loads(pathlib.Path(sys.argv[2]).read_text())
one_ring = json.loads(pathlib.Path(sys.argv[3]).read_text())
two_ring = json.loads(pathlib.Path(sys.argv[4]).read_text())
out_baseline, out_left, out_right = map(pathlib.Path, sys.argv[5:8])

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
    if token not in source:
        raise SystemExit(f"validated harness drift: missing {token!r}")

baseline = source.replace('res://assets/npc_gate_06.glb', 'res://assets/npc_gate_01.glb')
baseline = baseline.replace('res://gate8_variant06_target_micropose_skin_result.json', 'res://baseline-result.json')
baseline = baseline.replace('EXPECTED_VERTICES := 24073', 'EXPECTED_VERTICES := 21044')
baseline = baseline.replace('"candidate_variant":6', '"candidate_variant":1')
baseline = baseline.replace('grand-bruxelles-gate8-variant06-target-micropose-skin-v1', 'grand-bruxelles-gate8-variant01-split-shoulder-baseline-v1')
baseline = baseline.replace('REJECT_VARIANT06_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED', 'SPLIT_SHOULDER_AB_BASELINE')

if one_ring.get('diagnostic_state') != 'ONE_RING_LOCAL_WEIGHT_CLIFFS_CONFIRMED' or one_ring.get('failures') != []:
    raise SystemExit('one-ring evidence drift')
if two_ring.get('diagnostic_state') != 'SHOULDER_TWO_RING_MIXED_TOPOLOGY' or two_ring.get('failures') != []:
    raise SystemExit('two-ring evidence drift')

op = contract['operator']
shoulders = [e for e in one_ring.get('edges', []) if e.get('family') == 'shoulder']
if len(shoulders) != 2:
    raise SystemExit(f'expected 2 shoulder edges, got {len(shoulders)}')


def influence_map(report: dict) -> dict[str, float]:
    out: dict[str, float] = {}
    for row in report.get('influences', []):
        name = str(row.get('bone', ''))
        if not name:
            raise SystemExit('missing bone name')
        out[name] = out.get(name, 0.0) + float(row['weight'])
    total = sum(out.values())
    if abs(total - 1.0) > 0.001:
        raise SystemExit(f'non-normalized evidence weights {total}')
    return out


def average_maps(maps: list[dict[str, float]]) -> dict[str, float]:
    keys = sorted({k for m in maps for k in m})
    result = {k: sum(m.get(k, 0.0) for m in maps) / len(maps) for k in keys}
    result = {k: v for k, v in result.items() if v > 1e-9}
    total = sum(result.values())
    if total <= 1e-9:
        raise SystemExit('zero consensus sum')
    return {k: v / total for k, v in result.items()}


def endpoint_roles(edge: dict) -> tuple[dict, dict]:
    a, b = edge['endpoint_a'], edge['endpoint_b']
    a_other, b_other = float(a['max_other_neighbor_weight_l1']), float(b['max_other_neighbor_weight_l1'])
    if a_other <= op['coherent_side_max_other_l1_max'] and b_other >= op['broad_side_max_other_l1_min']:
        return a, b
    if b_other <= op['coherent_side_max_other_l1_max'] and a_other >= op['broad_side_max_other_l1_min']:
        return b, a
    raise SystemExit(f"shoulder signature drift {edge.get('vertex_a')}:{edge.get('vertex_b')}")


def coherent_consensus(coherent: dict) -> tuple[dict[str, float], list[int]]:
    maps = [influence_map(coherent)]
    accepted: list[int] = []
    for n in coherent.get('neighbors', []):
        if bool(n.get('is_worst_pair_endpoint')):
            continue
        if float(n.get('weight_l1', 999.0)) <= op['consensus_neighbor_l1_max']:
            maps.append(influence_map(n))
            accepted.append(int(n['vertex']))
    if len(maps) < 2:
        raise SystemExit('coherent consensus too small')
    return average_maps(maps), accepted

by_broad = {int(r['broad_vertex']): r for r in two_ring.get('shoulders', [])}
left_vectors: dict[str, dict[str, float]] = {}
right_vectors: dict[str, dict[str, float]] = {}
report = {'left': {}, 'right': {}}
for edge in shoulders:
    coherent, broad = endpoint_roles(edge)
    surface = str(edge['surface'])
    broad_vertex = int(broad['vertex'])
    consensus, accepted = coherent_consensus(coherent)
    topo = by_broad.get(broad_vertex)
    if topo is None:
        raise SystemExit(f'missing two-ring shoulder {broad_vertex}')
    if broad_vertex == int(contract['left']['broad_vertex']):
        if int(topo['broad_like_count']) != 0:
            raise SystemExit('left endpoint no longer isolated')
        left_vectors[f'{surface}|{broad_vertex}'] = consensus
        report['left'] = {'surface': surface, 'corrected_vertices': [broad_vertex], 'coherent_vertex': int(coherent['vertex']), 'accepted_consensus_neighbors': accepted}
    elif broad_vertex == int(contract['right']['broad_vertex']):
        cluster = [broad_vertex] + sorted(int(x['vertex']) for x in topo.get('two_ring', []) if x.get('classification') == 'broad_like')
        expected = sorted(int(v) for v in contract['right']['cluster_vertices'])
        if sorted(cluster) != expected:
            raise SystemExit(f'right cluster drift {cluster} != {expected}')
        for vi in cluster:
            right_vectors[f'{surface}|{vi}'] = consensus
        report['right'] = {'surface': surface, 'corrected_vertices': cluster, 'coherent_vertex': int(coherent['vertex']), 'accepted_consensus_neighbors': accepted}
    else:
        raise SystemExit(f'unexpected broad shoulder vertex {broad_vertex}')

if len(left_vectors) != 1 or len(right_vectors) != len(contract['right']['cluster_vertices']):
    raise SystemExit('corrected vertex count drift')


def inject_candidate(base: str, output_name: str, format_name: str, state_name: str, const_name: str, vectors: dict[str, dict[str, float]], metadata_name: str) -> str:
    text = base.replace('res://baseline-result.json', output_name)
    text = text.replace('grand-bruxelles-gate8-variant01-split-shoulder-baseline-v1', format_name)
    text = text.replace('SPLIT_SHOULDER_AB_BASELINE', state_name)
    marker = 'const COMMON_ROTATION_EPS_DEG := 0.01\n'
    if marker not in text:
        raise SystemExit('constant insertion marker missing')
    text = text.replace(marker, marker + f'const {const_name} := {json.dumps(vectors, sort_keys=True, separators=(",", ":"))}\n', 1)
    text = text.replace('var n := int(bb.size() / vv.size())\n            var posed := PackedVector3Array()', 'var n := int(bb.size() / vv.size())\n            var surface_key := _surface_key(mi, s)\n            var posed := PackedVector3Array()', 1)
    text = text.replace('posed[vi] = common_inverse * _skin_vertex(skin, vv[vi], bb, ww, vi, n)', f'posed[vi] = common_inverse * _skin_vertex_split_shoulder(surface_key, skin, vv[vi], bb, ww, vi, n, {const_name})', 1)
    text = text.replace('result[_surface_key(mi, s)] = posed', 'result[surface_key] = posed', 1)
    insert_before = 'func _skin_vertex(skin: Skin, vertex: Vector3, bones, weights, vi: int, n: int) -> Vector3:\n'
    helper = r'''func _skin_vertex_split_shoulder(surface_key: String, skin: Skin, vertex: Vector3, bones, weights, vi: int, n: int, corrections: Dictionary) -> Vector3:
    var correction_key := "%s|%d" % [surface_key, vi]
    if not corrections.has(correction_key):
        return _skin_vertex(skin, vertex, bones, weights, vi, n)
    var corrected: Dictionary = corrections[correction_key]
    var out := Vector3.ZERO
    var total := 0.0
    for bone_name_value in corrected.keys():
        var bone_name := String(bone_name_value)
        var weight := float(corrected[bone_name_value])
        if weight <= 0.0:
            continue
        var bone_idx := target.find_bone(bone_name)
        if bone_idx < 0:
            failures.append("split_shoulder_bone_missing=%s" % bone_name)
            continue
        var bind_idx := _find_skin_bind_for_bone_split(skin, bone_idx)
        if bind_idx < 0:
            failures.append("split_shoulder_bind_missing=%s" % bone_name)
            continue
        out += (target.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_idx) * vertex) * weight
        total += weight
    if total <= 0.000001:
        failures.append("split_shoulder_zero_weight=%s" % correction_key)
        return _skin_vertex(skin, vertex, bones, weights, vi, n)
    return out / total

func _find_skin_bind_for_bone_split(skin: Skin, bone_idx: int) -> int:
    for bind_idx in range(skin.get_bind_count()):
        if _resolve_skin_bone(skin, bind_idx) == bone_idx:
            return bind_idx
    return -1

'''
    if insert_before not in text:
        raise SystemExit('skin insertion marker missing')
    text = text.replace(insert_before, helper + insert_before, 1)
    meta_marker = '        "measurement":"target_only_controlled_micropose_cpu_skin_space",\n'
    if meta_marker not in text:
        raise SystemExit('metadata marker missing')
    text = text.replace(meta_marker, meta_marker + f'        "{metadata_name}":true,\n        "canonical_glb_modified":false,\n        "candidate_corrected_vertex_count":{const_name}.size(),\n', 1)
    if 'RetargetModifier3D' in text:
        raise SystemExit('retarget rail violated')
    return text

left = inject_candidate(baseline, 'res://left-result.json', 'grand-bruxelles-gate8-variant01-left-isolated-shoulder-candidate-v1', 'LEFT_ISOLATED_SHOULDER_AB_CANDIDATE', 'LEFT_SHOULDER_WEIGHTS', left_vectors, 'left_isolated_shoulder_candidate')
right = inject_candidate(baseline, 'res://right-result.json', 'grand-bruxelles-gate8-variant01-right-cluster-shoulder-candidate-v1', 'RIGHT_CLUSTER_SHOULDER_AB_CANDIDATE', 'RIGHT_SHOULDER_WEIGHTS', right_vectors, 'right_cluster_shoulder_candidate')

for frozen in ('MICROPOSE_DEG := 5.0', 'MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25', 'MAX_EDGE_STRETCH_RATIO := 3.0', 'MIN_EDGE_COMPRESSION_RATIO := 0.25'):
    for text in (baseline, left, right):
        if frozen not in text:
            raise SystemExit(f'frozen rail drift {frozen}')

out_baseline.write_text(baseline)
out_left.write_text(left)
out_right.write_text(right)
print(json.dumps({'operator': 'split_shoulder_topology_aware', 'left_corrected_vertex_count': len(left_vectors), 'right_corrected_vertex_count': len(right_vectors), 'report': report}, indent=2, sort_keys=True))
