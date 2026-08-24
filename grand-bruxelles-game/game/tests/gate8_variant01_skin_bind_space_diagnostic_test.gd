extends SceneTree

const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const MAX_REST_RECONSTRUCTION_ERROR_M := 0.001

var _failures: Array[String] = []
var _target: Skeleton3D
var _meshes: Array[MeshInstance3D] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var target_packed := load(TARGET_SCENE) as PackedScene
    if target_packed == null:
        _failures.append("target_load_failed")
        _finish({})
        return
    var target_scene := target_packed.instantiate() as Node3D
    if target_scene == null:
        _failures.append("target_instance_failed")
        _finish({})
        return
    root.add_child(target_scene)
    await process_frame
    await process_frame
    _target = _find_skeleton(target_scene)
    _collect_skinned_meshes(target_scene, _meshes)
    if _target == null:
        _failures.append("target_skeleton_missing")
    if _meshes.is_empty():
        _failures.append("target_skinned_meshes_missing")
    if not _failures.is_empty():
        _finish({})
        return

    _target.reset_bone_poses()
    _target.force_update_all_bone_transforms()

    var legacy_max_error := 0.0
    var corrected_max_error := 0.0
    var worst_legacy := {}
    var worst_corrected := {}
    var vertices_measured := 0
    var surfaces_measured := 0
    var max_mesh_to_skeleton_translation := 0.0

    for mesh_instance: MeshInstance3D in _meshes:
        if mesh_instance.mesh == null or mesh_instance.skin == null:
            _failures.append("mesh_or_skin_missing=%s" % mesh_instance.name)
            continue
        var mesh_to_skeleton: Transform3D = _target.global_transform.affine_inverse() * mesh_instance.global_transform
        max_mesh_to_skeleton_translation = maxf(max_mesh_to_skeleton_translation, mesh_to_skeleton.origin.length())
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
                var vertex: Vector3 = vertices[vertex_idx]
                var legacy: Vector3 = _skin_vertex_legacy(mesh_instance.skin, vertex, bones, weights, vertex_idx)
                var corrected: Vector3 = _skin_vertex_mesh_space(mesh_instance, mesh_instance.skin, vertex, bones, weights, vertex_idx)
                var legacy_error: float = legacy.distance_to(vertex)
                var corrected_error: float = corrected.distance_to(vertex)
                vertices_measured += 1
                if legacy_error > legacy_max_error:
                    legacy_max_error = legacy_error
                    worst_legacy = _worst_row(mesh_instance, surface_idx, vertex_idx, legacy_error)
                if corrected_error > corrected_max_error:
                    corrected_max_error = corrected_error
                    worst_corrected = _worst_row(mesh_instance, surface_idx, vertex_idx, corrected_error)

    if vertices_measured <= 0 or surfaces_measured <= 0:
        _failures.append("no_skin_vertices_measured")

    var corrected_valid := corrected_max_error <= MAX_REST_RECONSTRUCTION_ERROR_M
    var legacy_valid := legacy_max_error <= MAX_REST_RECONSTRUCTION_ERROR_M
    var state := "MESH_SPACE_BIND_RECONSTRUCTION_VALID" if corrected_valid else "BIND_SPACE_RECONSTRUCTION_UNRESOLVED"
    var result := {
        "format": "grand-bruxelles-gate8-skin-bind-space-diagnostic-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "skinned_mesh_count": _meshes.size(),
        "surfaces_measured": surfaces_measured,
        "vertices_measured": vertices_measured,
        "legacy_rest_reconstruction_max_error_m": legacy_max_error,
        "mesh_space_rest_reconstruction_max_error_m": corrected_max_error,
        "max_rest_reconstruction_error_allowed_m": MAX_REST_RECONSTRUCTION_ERROR_M,
        "legacy_formula_rest_valid": legacy_valid,
        "mesh_space_formula_rest_valid": corrected_valid,
        "max_mesh_to_skeleton_translation_m": max_mesh_to_skeleton_translation,
        "worst_legacy": worst_legacy,
        "worst_mesh_space": worst_corrected,
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
        "failures": _failures
    }
    _write_result(result)
    print("GATE8_SKIN_BIND_SPACE state=%s legacy_error_m=%.9f mesh_space_error_m=%.9f meshes=%d vertices=%d" % [state, legacy_max_error, corrected_max_error, _meshes.size(), vertices_measured])
    _finish(result)

func _skin_vertex_legacy(skin: Skin, vertex: Vector3, bones, weights, vertex_idx: int) -> Vector3:
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
            _failures.append("legacy_skin_bind_unresolved=%d" % bind_idx)
            continue
        out += (_target.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_idx) * vertex) * weight
        weight_sum += weight
    return vertex if weight_sum <= 0.000001 else out / weight_sum

func _skin_vertex_mesh_space(mesh_instance: MeshInstance3D, skin: Skin, vertex: Vector3, bones, weights, vertex_idx: int) -> Vector3:
    var mesh_to_skeleton: Transform3D = _target.global_transform.affine_inverse() * mesh_instance.global_transform
    var skeleton_to_mesh: Transform3D = mesh_to_skeleton.affine_inverse()
    var vertex_in_skeleton: Vector3 = mesh_to_skeleton * vertex
    var out_in_skeleton := Vector3.ZERO
    var weight_sum := 0.0
    for influence_idx: int in range(4):
        var offset := vertex_idx * 4 + influence_idx
        var weight := float(weights[offset])
        if weight <= 0.0:
            continue
        var bind_idx := int(bones[offset])
        var bone_idx := _resolve_skin_bone(skin, bind_idx)
        if bone_idx < 0:
            _failures.append("mesh_space_skin_bind_unresolved=%d" % bind_idx)
            continue
        out_in_skeleton += (_target.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_idx) * vertex_in_skeleton) * weight
        weight_sum += weight
    if weight_sum <= 0.000001:
        return vertex
    return skeleton_to_mesh * (out_in_skeleton / weight_sum)

func _resolve_skin_bone(skin: Skin, bind_idx: int) -> int:
    if bind_idx < 0 or bind_idx >= skin.get_bind_count():
        _failures.append("bind_index_out_of_range=%d" % bind_idx)
        return -1
    var bind_name := String(skin.get_bind_name(bind_idx))
    if not bind_name.is_empty():
        return _target.find_bone(bind_name)
    return skin.get_bind_bone(bind_idx)

func _worst_row(mesh_instance: MeshInstance3D, surface_idx: int, vertex_idx: int, error_m: float) -> Dictionary:
    return {
        "mesh": String(mesh_instance.get_path()),
        "surface": surface_idx,
        "vertex": vertex_idx,
        "error_m": error_m
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
    var file := FileAccess.open("res://gate8_variant01_skin_bind_space_diagnostic_result.json", FileAccess.WRITE)
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
