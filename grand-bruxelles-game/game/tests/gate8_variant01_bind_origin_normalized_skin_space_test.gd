extends "res://game/tests/gate8_variant01_skin_space_deformation_diagnostic_test.gd"

const COMMON_TRANSLATION_EPS_M := 0.00001
const COMMON_ROTATION_EPS_DEG := 0.01
const NONIDENTITY_TRANSLATION_MIN_M := 0.05
const EXPECTED_MIN_ABSOLUTE_EDGE_CHANGE_M := 0.5

var _common_inverse := Transform3D.IDENTITY
var _common_ready := false
var _common_origin_translation_m := 0.0
var _common_origin_rotation_deg := 0.0
var _max_product_translation_delta_m := 0.0
var _max_product_rotation_delta_deg := 0.0
var _bind_observations := 0

func _capture_skinned_positions() -> Dictionary:
    var result: Dictionary = super._capture_skinned_positions()
    if not _ensure_common_bind_origin():
        return result
    for key in result.keys():
        var vertices: PackedVector3Array = result[key]
        for vertex_idx: int in range(vertices.size()):
            vertices[vertex_idx] = _common_inverse * vertices[vertex_idx]
        result[key] = vertices
    return result

func _measure_edge_distortion(rest_positions: Dictionary, posed_positions: Dictionary) -> Dictionary:
    var row: Dictionary = super._measure_edge_distortion(rest_positions, posed_positions)
    var max_abs_change := 0.0
    var max_abs_row: Dictionary = {}
    for mesh_instance: MeshInstance3D in _meshes:
        if mesh_instance.mesh == null or mesh_instance.skin == null:
            continue
        var mesh: Mesh = mesh_instance.mesh
        for surface_idx: int in range(mesh.get_surface_count()):
            if mesh.surface_get_primitive_type(surface_idx) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            var key := _surface_key(mesh_instance, surface_idx)
            if not rest_positions.has(key) or not posed_positions.has(key):
                continue
            var arrays: Array = mesh.surface_get_arrays(surface_idx)
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            var bones = arrays[Mesh.ARRAY_BONES]
            var weights = arrays[Mesh.ARRAY_WEIGHTS]
            var rest: PackedVector3Array = rest_positions[key]
            var posed: PackedVector3Array = posed_positions[key]
            var triangle_count := indices.size() / 3 if not indices.is_empty() else rest.size() / 3
            for tri_idx: int in range(triangle_count):
                var ids := PackedInt32Array()
                ids.resize(3)
                for corner: int in range(3):
                    ids[corner] = indices[tri_idx * 3 + corner] if not indices.is_empty() else tri_idx * 3 + corner
                var pairs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 0)]
                for pair: Vector2i in pairs:
                    var a := int(ids[pair.x])
                    var b := int(ids[pair.y])
                    if a < 0 or b < 0 or a >= rest.size() or b >= rest.size():
                        continue
                    var rest_len := rest[a].distance_to(rest[b])
                    if rest_len <= 0.000001:
                        continue
                    var posed_len := posed[a].distance_to(posed[b])
                    var abs_change := absf(posed_len - rest_len)
                    if abs_change > max_abs_change:
                        max_abs_change = abs_change
                        max_abs_row = {
                            "surface": key,
                            "surface_index": surface_idx,
                            "triangle": tri_idx,
                            "edge_corners": [pair.x, pair.y],
                            "vertex_a": a,
                            "vertex_b": b,
                            "rest_length_m": rest_len,
                            "posed_length_m": posed_len,
                            "absolute_edge_length_change_m": abs_change,
                            "stretch_ratio": posed_len / rest_len,
                            "endpoint_a_displacement_m": rest[a].distance_to(posed[a]),
                            "endpoint_b_displacement_m": rest[b].distance_to(posed[b]),
                            "vertex_a_influences": _vertex_influences(mesh_instance.skin, bones, weights, a),
                            "vertex_b_influences": _vertex_influences(mesh_instance.skin, bones, weights, b),
                        }
    row["max_edge_absolute_change_m"] = max_abs_change
    row["max_absolute_edge"] = max_abs_row
    return row

func _write_result(result: Dictionary) -> void:
    var max_abs_change := 0.0
    var max_abs_clip := ""
    var max_abs_edge: Dictionary = {}
    var clips: Dictionary = result.get("clips", {})
    for clip in clips.keys():
        var clip_row: Dictionary = clips[clip]
        var value := float(clip_row.get("max_edge_absolute_change_m", 0.0))
        if value > max_abs_change:
            max_abs_change = value
            max_abs_clip = String(clip)
            max_abs_edge = clip_row.get("max_absolute_edge", {})
    if max_abs_change < EXPECTED_MIN_ABSOLUTE_EDGE_CHANGE_M:
        _failures.append("known_absolute_skin_deformation_not_reproduced=%.6f" % max_abs_change)
    result["format"] = "grand-bruxelles-gate8-bind-origin-normalized-skin-space-v1"
    result["bind_origin_normalized_baseline"] = true
    result["common_bind_origin_translation_m"] = _common_origin_translation_m
    result["common_bind_origin_rotation_deg"] = _common_origin_rotation_deg
    result["max_product_translation_delta_m"] = _max_product_translation_delta_m
    result["max_product_rotation_delta_deg"] = _max_product_rotation_delta_deg
    result["bind_observations"] = _bind_observations
    result["max_absolute_edge_length_change_m"] = max_abs_change
    result["max_absolute_edge_clip"] = max_abs_clip
    result["max_absolute_edge"] = max_abs_edge
    result["expected_min_absolute_edge_change_m"] = EXPECTED_MIN_ABSOLUTE_EDGE_CHANGE_M
    result["failures"] = _failures
    var file := FileAccess.open("res://gate8_variant01_bind_origin_normalized_skin_space_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("normalized_result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "\t"))
    file.close()

func _ensure_common_bind_origin() -> bool:
    if _common_ready:
        return true
    if _target == null or _meshes.is_empty():
        _failures.append("common_bind_origin_prerequisites_missing")
        return false
    var reference := Transform3D.IDENTITY
    var have_reference := false
    for mesh_instance: MeshInstance3D in _meshes:
        var skin := mesh_instance.skin
        if skin == null:
            continue
        for bind_idx: int in range(skin.get_bind_count()):
            var bone_idx := _resolve_skin_bone(skin, bind_idx)
            if bone_idx < 0:
                _failures.append("normalized_bind_unresolved=%d" % bind_idx)
                continue
            var product := _target.get_bone_global_rest(bone_idx) * skin.get_bind_pose(bind_idx)
            if not have_reference:
                reference = product
                have_reference = true
            else:
                _max_product_translation_delta_m = maxf(_max_product_translation_delta_m, reference.origin.distance_to(product.origin))
                _max_product_rotation_delta_deg = maxf(_max_product_rotation_delta_deg, _basis_delta_deg(reference.basis, product.basis))
            _bind_observations += 1
    if not have_reference:
        _failures.append("normalized_bind_origin_missing")
        return false
    _common_origin_translation_m = reference.origin.length()
    _common_origin_rotation_deg = _basis_delta_deg(Basis.IDENTITY, reference.basis)
    if _common_origin_translation_m < NONIDENTITY_TRANSLATION_MIN_M:
        _failures.append("normalized_common_origin_not_reproduced=%.9f" % _common_origin_translation_m)
    if _max_product_translation_delta_m > COMMON_TRANSLATION_EPS_M:
        _failures.append("normalized_common_translation_spread=%.9f" % _max_product_translation_delta_m)
    if _max_product_rotation_delta_deg > COMMON_ROTATION_EPS_DEG:
        _failures.append("normalized_common_rotation_spread=%.9f" % _max_product_rotation_delta_deg)
    _common_inverse = reference.affine_inverse()
    _common_ready = _failures.is_empty()
    return _common_ready

func _basis_delta_deg(a: Basis, b: Basis) -> float:
    var qa := a.orthonormalized().get_rotation_quaternion().normalized()
    var qb := b.orthonormalized().get_rotation_quaternion().normalized()
    return rad_to_deg(qa.angle_to(qb))
