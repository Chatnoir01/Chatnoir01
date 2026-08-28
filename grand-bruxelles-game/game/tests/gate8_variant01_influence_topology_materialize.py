from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 4:
    raise SystemExit("usage: materialize.py SOURCE_GD OUT_GD OUTPUT_JSON")

src_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
output_json = sys.argv[3]
text = src_path.read_text()

required = [
    'const TARGET_SCENE := "res://assets/npc_gate_06.glb"',
    'const EXPECTED_VERTICES := 24073',
    'const MICROPOSE_DEG := 5.0',
    'const MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25',
    'const MAX_EDGE_STRETCH_RATIO := 3.0',
    'const MIN_EDGE_COMPRESSION_RATIO := 0.25',
    'var edge := _measure_edge_distortion(rest_positions, posed_positions)',
    'func _measure_edge_distortion(rest_positions: Dictionary, posed_positions: Dictionary) -> Dictionary:',
    'max_row = {"surface":key,"triangle":tri,"edge":String(pair[2]),"vertex_a":a,"vertex_b":b,"rest_length_m":rl,"posed_length_m":pl,"absolute_edge_length_change_m":change,"stretch_ratio":ratio}',
    '"candidate_variant":6',
]
for token in required:
    if token not in text:
        raise SystemExit(f"validated harness drift: missing {token!r}")

text = text.replace('res://assets/npc_gate_06.glb', 'res://assets/npc_gate_01.glb')
text = text.replace('res://gate8_variant06_target_micropose_skin_result.json', f'res://{output_json}')
text = text.replace('EXPECTED_VERTICES := 24073', 'EXPECTED_VERTICES := 21044')
text = text.replace('"candidate_variant":6', '"candidate_variant":1')
text = text.replace('grand-bruxelles-gate8-variant06-target-micropose-skin-v1', 'grand-bruxelles-gate8-variant01-influence-topology-measurement-v1')
text = text.replace('REJECT_VARIANT06_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED', 'DIAGNOSE_INFLUENCE_TOPOLOGY')
text = text.replace(
    'var edge := _measure_edge_distortion(rest_positions, posed_positions)',
    'var edge := _measure_edge_distortion(rest_positions, posed_positions, bone_idx)',
    1,
)
text = text.replace(
    'func _measure_edge_distortion(rest_positions: Dictionary, posed_positions: Dictionary) -> Dictionary:',
    'func _measure_edge_distortion(rest_positions: Dictionary, posed_positions: Dictionary, rotated_bone_idx: int) -> Dictionary:',
    1,
)
old_row = 'max_row = {"surface":key,"triangle":tri,"edge":String(pair[2]),"vertex_a":a,"vertex_b":b,"rest_length_m":rl,"posed_length_m":pl,"absolute_edge_length_change_m":change,"stretch_ratio":ratio}'
new_row = old_row + '\n                        max_row["influence_topology"] = _describe_edge_topology(key, a, b, rotated_bone_idx)'
text = text.replace(old_row, new_row, 1)

row_marker = '                    "min_edge_compression_ratio": compression, "max_foot_drift_m": foot_drift,\n                    "within_gates": within\n'
if row_marker not in text:
    raise SystemExit('validated harness drift: case row marker missing')
text = text.replace(
    row_marker,
    '                    "min_edge_compression_ratio": compression, "max_foot_drift_m": foot_drift,\n'
    '                    "within_gates": within,\n'
    '                    "worst_edge": (edge["max_absolute_edge"] as Dictionary).duplicate(true)\n',
    1,
)

insert_before = 'func _measure_edge_distortion(rest_positions: Dictionary, posed_positions: Dictionary, rotated_bone_idx: int) -> Dictionary:\n'
helper = r'''func _describe_edge_topology(surface_key: String, vertex_a: int, vertex_b: int, rotated_bone_idx: int) -> Dictionary:
    for mi in meshes:
        for s in range(mi.mesh.get_surface_count()):
            if _surface_key(mi, s) != surface_key:
                continue
            var arrays := mi.mesh.surface_get_arrays(s)
            var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var bb = arrays[Mesh.ARRAY_BONES]
            var ww = arrays[Mesh.ARRAY_WEIGHTS]
            if vv.is_empty() or bb.size() != ww.size() or bb.size() % vv.size() != 0:
                return {"classification":"invalid_skin_arrays"}
            var n := int(bb.size() / vv.size())
            var a := _vertex_influences(mi.skin, bb, ww, vertex_a, n)
            var b := _vertex_influences(mi.skin, bb, ww, vertex_b, n)
            var names_a: Array[String] = []
            var names_b: Array[String] = []
            for row in a:
                names_a.append(String(row["bone"]))
            for row in b:
                names_b.append(String(row["bone"]))
            var shared: Array[String] = []
            for name in names_a:
                if name in names_b:
                    shared.append(name)
            var rotated_name := String(target.get_bone_name(rotated_bone_idx))
            var rotated_weight_a := _weight_for_bone(a, rotated_name)
            var rotated_weight_b := _weight_for_bone(b, rotated_name)
            var classification := "shared_influences"
            if shared.is_empty():
                classification = "disjoint_influences"
            elif (rotated_weight_a > 0.0) != (rotated_weight_b > 0.0):
                classification = "rotated_bone_one_sided"
            elif absf(rotated_weight_a - rotated_weight_b) >= 0.50:
                classification = "rotated_bone_weight_discontinuity"
            return {
                "classification":classification,
                "rotated_bone":rotated_name,
                "rotated_weight_a":rotated_weight_a,
                "rotated_weight_b":rotated_weight_b,
                "rotated_weight_delta":absf(rotated_weight_a-rotated_weight_b),
                "shared_bones":shared,
                "shared_bone_count":shared.size(),
                "vertex_a_influences":a,
                "vertex_b_influences":b,
                "vertex_a_weight_sum":_weight_sum(a),
                "vertex_b_weight_sum":_weight_sum(b)
            }
    return {"classification":"surface_not_found"}

func _vertex_influences(skin: Skin, bones, weights, vi: int, n: int) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for j in range(n):
        var off := vi * n + j
        var w := float(weights[off])
        if w <= 0.0:
            continue
        var bind_idx := int(bones[off])
        if bind_idx < 0 or bind_idx >= skin.get_bind_count():
            continue
        var bone_idx := _resolve_skin_bone(skin, bind_idx)
        if bone_idx < 0:
            continue
        out.append({"bone":String(target.get_bone_name(bone_idx)),"bone_index":bone_idx,"bind_index":bind_idx,"weight":w})
    out.sort_custom(func(x: Dictionary, y: Dictionary): return float(x["weight"]) > float(y["weight"]))
    return out

func _weight_for_bone(rows: Array[Dictionary], bone_name: String) -> float:
    for row in rows:
        if String(row["bone"]) == bone_name:
            return float(row["weight"])
    return 0.0

func _weight_sum(rows: Array[Dictionary]) -> float:
    var total := 0.0
    for row in rows:
        total += float(row["weight"])
    return total

'''
if insert_before not in text:
    raise SystemExit('measure function insertion marker missing')
text = text.replace(insert_before, helper + insert_before, 1)

meta_needle = '        "measurement":"target_only_controlled_micropose_cpu_skin_space",\n'
if meta_needle not in text:
    raise SystemExit('metadata marker missing')
text = text.replace(
    meta_needle,
    meta_needle + '        "influence_topology_diagnostic":true,\n        "canonical_glb_modified":false,\n',
    1,
)

if 'RetargetModifier3D' in text:
    raise SystemExit('retarget rail violated')
for frozen in ('MICROPOSE_DEG := 5.0', 'MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25', 'MAX_EDGE_STRETCH_RATIO := 3.0', 'MIN_EDGE_COMPRESSION_RATIO := 0.25'):
    if frozen not in text:
        raise SystemExit(f'frozen rail drift: {frozen}')

out_path.write_text(text)
