extends SceneTree

const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const EXPECTED_BONES := 53
const EXPECTED_SKINNED_MESHES := 8
const COMMON_TRANSLATION_EPS_M := 0.00001
const COMMON_ROTATION_EPS_DEG := 0.01
const COMPENSATED_RECONSTRUCTION_EPS_M := 0.001
const NONIDENTITY_TRANSLATION_MIN_M := 0.05

var _failures: Array[String] = []
var _target: Skeleton3D
var _meshes: Array[MeshInstance3D] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load(TARGET_SCENE) as PackedScene
    if packed == null:
        _failures.append("target_load_failed")
        _finish({})
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _failures.append("target_instance_failed")
        _finish({})
        return
    root.add_child(scene)
    await process_frame
    await process_frame

    _target = _find_skeleton(scene)
    _collect_skinned_meshes(scene, _meshes)
    if _target == null:
        _failures.append("target_skeleton_missing")
    if _meshes.size() != EXPECTED_SKINNED_MESHES:
        _failures.append("skinned_mesh_count=%d" % _meshes.size())
    if _target != null and _target.get_bone_count() != EXPECTED_BONES:
        _failures.append("target_bone_count=%d" % _target.get_bone_count())
    if not _failures.is_empty():
        _finish({})
        return

    _target.reset_bone_poses()
    _target.force_update_all_bone_transforms()

    var reference_product := Transform3D.IDENTITY
    var reference_set := false
    var bind_observations := 0
    var covered_bones: Dictionary = {}
    var max_product_translation_delta := 0.0
    var max_product_rotation_delta := 0.0
    var product_rows: Array[Dictionary] = []

    for mesh_instance: MeshInstance3D in _meshes:
        var skin := mesh_instance.skin
        if skin == null:
            _failures.append("skin_missing=%s" % mesh_instance.name)
            continue
        for bind_idx: int in range(skin.get_bind_count()):
            var bone_idx := _resolve_skin_bone(skin, bind_idx)
            if bone_idx < 0:
                _failures.append("bind_unresolved mesh=%s bind=%d" % [mesh_instance.name, bind_idx])
                continue
            var product := _global_rest(bone_idx) * skin.get_bind_pose(bind_idx)
            if not reference_set:
                reference_product = product
                reference_set = true
            var translation_delta := product.origin.distance_to(reference_product.origin)
            var rotation_delta := _basis_delta_deg(product.basis, reference_product.basis)
            max_product_translation_delta = maxf(max_product_translation_delta, translation_delta)
            max_product_rotation_delta = maxf(max_product_rotation_delta, rotation_delta)
            covered_bones[bone_idx] = true
            bind_observations += 1
            product_rows.append({
                "mesh": String(mesh_instance.get_path()),
                "bind_index": bind_idx,
                "bind_name": String(skin.get_bind_name(bind_idx)),
                "bone_index": bone_idx,
                "bone_name": _target.get_bone_name(bone_idx),
                "translation_delta_from_reference_m": translation_delta,
                "rotation_delta_from_reference_deg": rotation_delta,
            })

    if not reference_set:
        _failures.append("no_bind_products_measured")
        _finish({})
        return
    if covered_bones.size() != EXPECTED_BONES:
        _failures.append("covered_bone_count=%d" % covered_bones.size())

    var uncompensated_max_error := 0.0
    var compensated_max_error := 0.0
    var vertices_measured := 0
    var surfaces_measured := 0
    var worst_uncompensated: Dictionary = {}
    var worst_compensated: Dictionary = {}
    var common_inverse := reference_product.affine_inverse()

    for mesh_instance: MeshInstance3D in _meshes:
        if mesh_instance.mesh == null or mesh_instance.skin == null:
            _failures.append("mesh_or_skin_missing=%s" % mesh_instance.name)
            continue
        var mesh: Mesh = mesh_instance.mesh
        for surface_idx: int in range(mesh.get_surface_count()):
            if mesh.surface_get_primitive_type(surface_idx) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            var arrays: Array = mesh.surface_get_arrays(surface_idx)
            if arrays.size() <= Mesh.ARRAY_WEIGHTS:
                _failures.append("surface_arrays_incomplete mesh=%s surface=%d" % [mesh_instance.name, surface_idx])
                continue
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var bones = arrays[Mesh.ARRAY_BONES]
            var weights = arrays[Mesh.ARRAY_WEIGHTS]
            if vertices.is_empty() or bones.size() != vertices.size() * 4 or weights.size() != vertices.size() * 4:
                _failures.append("skin_array_shape_invalid mesh=%s surface=%d vertices=%d bones=%d weights=%d" % [mesh_instance.name, surface_idx, vertices.size(), bones.size(), weights.size()])
                continue
            surfaces_measured += 1
            for vertex_idx: int in range(vertices.size()):
                var vertex := vertices[vertex_idx]
                var uncompensated := _skin_rest_vertex(mesh_instance.skin, vertex, bones, weights, vertex_idx, Transform3D.IDENTITY)
                var compensated := _skin_rest_vertex(mesh_instance.skin, vertex, bones, weights, vertex_idx, common_inverse)
                var uncompensated_error := uncompensated.distance_to(vertex)
                var compensated_error := compensated.distance_to(vertex)
                vertices_measured += 1
                if uncompensated_error > uncompensated_max_error:
                    uncompensated_max_error = uncompensated_error
                    worst_uncompensated = _worst_row(mesh_instance, surface_idx, vertex_idx, uncompensated_error)
                if compensated_error > compensated_max_error:
                    compensated_max_error = compensated_error
                    worst_compensated = _worst_row(mesh_instance, surface_idx, vertex_idx, compensated_error)

    if vertices_measured <= 0 or surfaces_measured <= 0:
        _failures.append("no_skin_vertices_measured")

    var reference_translation_m := reference_product.origin.length()
    var reference_rotation_deg := _basis_delta_deg(Basis.IDENTITY, reference_product.basis)
    var common_transform_consistent := max_product_translation_delta <= COMMON_TRANSLATION_EPS_M and max_product_rotation_delta <= COMMON_ROTATION_EPS_DEG
    var compensated_reconstruction_valid := compensated_max_error <= COMPENSATED_RECONSTRUCTION_EPS_M
    var nonidentity_origin_present := reference_translation_m >= NONIDENTITY_TRANSLATION_MIN_M

    if not common_transform_consistent:
        _failures.append("bind_products_not_common translation=%.9f rotation=%.9f" % [max_product_translation_delta, max_product_rotation_delta])
    if not compensated_reconstruction_valid:
        _failures.append("compensated_reconstruction_error_m=%.9f" % compensated_max_error)
    if not nonidentity_origin_present:
        _failures.append("expected_nonidentity_bind_origin_missing=%.9f" % reference_translation_m)

    var state := "COMMON_BIND_ORIGIN_CONVENTION_CONFIRMED" if _failures.is_empty() else "BIND_ORIGIN_CONVENTION_UNRESOLVED"
    var result := {
        "format": "grand-bruxelles-gate8-bind-origin-convention-diagnostic-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "target_bone_count": _target.get_bone_count(),
        "skinned_mesh_count": _meshes.size(),
        "surfaces_measured": surfaces_measured,
        "vertices_measured": vertices_measured,
        "bind_observations": bind_observations,
        "covered_bone_count": covered_bones.size(),
        "reference_product_origin": _vec3_row(reference_product.origin),
        "reference_product_translation_m": reference_translation_m,
        "reference_product_rotation_deg": reference_rotation_deg,
        "max_product_translation_delta_m": max_product_translation_delta,
        "max_product_rotation_delta_deg": max_product_rotation_delta,
        "common_translation_epsilon_m": COMMON_TRANSLATION_EPS_M,
        "common_rotation_epsilon_deg": COMMON_ROTATION_EPS_DEG,
        "uncompensated_rest_reconstruction_max_error_m": uncompensated_max_error,
        "compensated_rest_reconstruction_max_error_m": compensated_max_error,
        "compensated_reconstruction_epsilon_m": COMPENSATED_RECONSTRUCTION_EPS_M,
        "nonidentity_translation_min_m": NONIDENTITY_TRANSLATION_MIN_M,
        "common_transform_consistent": common_transform_consistent,
        "compensated_reconstruction_valid": compensated_reconstruction_valid,
        "nonidentity_origin_present": nonidentity_origin_present,
        "worst_uncompensated": worst_uncompensated,
        "worst_compensated": worst_compensated,
        "bind_products": product_rows,
        "diagnostic_state": state,
        "target_skin_modified": false,
        "target_rest_modified": false,
        "retarget_applied": false,
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_approval_claimed": false,
        "failures": _failures,
    }
    _write_result(result)
    print("GATE8_BIND_ORIGIN state=%s binds=%d bones=%d common_m=%.9f common_deg=%.9f raw_error_m=%.9f compensated_error_m=%.9f" % [state, bind_observations, covered_bones.size(), max_product_translation_delta, max_product_rotation_delta, uncompensated_max_error, compensated_max_error])
    _finish(result)

func _skin_rest_vertex(skin: Skin, vertex: Vector3, bones, weights, vertex_idx: int, compensation: Transform3D) -> Vector3:
    var out := Vector3.ZERO
    var weight_sum := 0.0
    for influence_idx: int in range(4):
        var offset := vertex_idx * 4 + influence_idx
        var weight := float(weights[offset])
        if weight <= 0.0:
            continue
        var bind_idx := int(bones[offset])
        var bone_idx := _resolve_skin_bone(skin, bind_idx)
        if bone_idx < 0:
            _failures.append("vertex_bind_unresolved=%d" % bind_idx)
            continue
        var rest_product := _global_rest(bone_idx) * skin.get_bind_pose(bind_idx)
        out += (compensation * rest_product * vertex) * weight
        weight_sum += weight
    return vertex if weight_sum <= 0.000001 else out / weight_sum

func _global_rest(bone_idx: int) -> Transform3D:
    var chain: Array[int] = []
    var current := bone_idx
    while current >= 0:
        chain.push_front(current)
        current = _target.get_bone_parent(current)
    var out := Transform3D.IDENTITY
    for idx: int in chain:
        out = out * _target.get_bone_rest(idx)
    return out

func _resolve_skin_bone(skin: Skin, bind_idx: int) -> int:
    if bind_idx < 0 or bind_idx >= skin.get_bind_count():
        return -1
    var bind_name := String(skin.get_bind_name(bind_idx))
    if not bind_name.is_empty():
        return _target.find_bone(bind_name)
    return skin.get_bind_bone(bind_idx)

func _basis_delta_deg(a: Basis, b: Basis) -> float:
    var qa := a.orthonormalized().get_rotation_quaternion().normalized()
    var qb := b.orthonormalized().get_rotation_quaternion().normalized()
    return rad_to_deg(qa.angle_to(qb))

func _vec3_row(value: Vector3) -> Dictionary:
    return {"x": value.x, "y": value.y, "z": value.z}

func _worst_row(mesh_instance: MeshInstance3D, surface_idx: int, vertex_idx: int, error_m: float) -> Dictionary:
    return {
        "mesh": String(mesh_instance.get_path()),
        "surface": surface_idx,
        "vertex": vertex_idx,
        "error_m": error_m,
    }

func _collect_skinned_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh != null and mesh_instance.skin != null:
            out.append(mesh_instance)
    for child in node.get_children():
        _collect_skinned_meshes(child, out)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_bind_origin_convention_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "\t"))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        quit(0)
    for failure: String in _failures:
        push_error(failure)
    quit(1)
