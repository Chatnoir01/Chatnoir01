extends SceneTree

const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const EXPECTED_BONES := 53
const EXPECTED_SKINNED_MESHES := 8
const COMMON_TRANSLATION_EPS_M := 0.00001
const COMMON_ROTATION_EPS_DEG := 0.01
const EDGE_LENGTH_EPS_M := 0.000001
const NONIDENTITY_TRANSLATION_MIN_M := 0.05

var _failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load(TARGET_SCENE) as PackedScene
    if packed == null:
        _fail("target_scene_missing")
        _finish({})
        return
    var root := packed.instantiate()
    get_root().add_child(root)
    await process_frame

    var skeleton := _find_skeleton(root)
    if skeleton == null:
        _fail("skeleton_missing")
        _finish({})
        return
    if skeleton.get_bone_count() != EXPECTED_BONES:
        _fail("unexpected_bone_count")

    var meshes: Array[MeshInstance3D] = []
    _collect_skinned_meshes(root, meshes)
    if meshes.size() != EXPECTED_SKINNED_MESHES:
        _fail("unexpected_skinned_mesh_count")

    var reference_product := Transform3D.IDENTITY
    var have_reference := false
    var bind_observations := 0
    var max_translation_spread := 0.0
    var max_rotation_spread_deg := 0.0
    var edge_observations := 0
    var max_edge_length_delta_m := 0.0

    for mesh_instance in meshes:
        var skin := mesh_instance.skin
        var mesh := mesh_instance.mesh
        if skin == null or mesh == null:
            _fail("skin_or_mesh_missing")
            continue
        for bind_idx in range(skin.get_bind_count()):
            var bone_name := skin.get_bind_name(bind_idx)
            var bone_idx := skeleton.find_bone(bone_name)
            if bone_idx < 0:
                _fail("bind_bone_missing:%s" % bone_name)
                continue
            var product := skeleton.get_bone_global_rest(bone_idx) * skin.get_bind_pose(bind_idx)
            if not have_reference:
                reference_product = product
                have_reference = true
            else:
                max_translation_spread = maxf(max_translation_spread, reference_product.origin.distance_to(product.origin))
                max_rotation_spread_deg = maxf(max_rotation_spread_deg, rad_to_deg(reference_product.basis.get_rotation_quaternion().angle_to(product.basis.get_rotation_quaternion())))
            bind_observations += 1

    if not have_reference:
        _fail("no_bind_reference")
    if max_translation_spread > COMMON_TRANSLATION_EPS_M:
        _fail("common_translation_spread_exceeded")
    if max_rotation_spread_deg > COMMON_ROTATION_EPS_DEG:
        _fail("common_rotation_spread_exceeded")
    if reference_product.origin.length() < NONIDENTITY_TRANSLATION_MIN_M:
        _fail("nonidentity_common_origin_not_reproduced")

    var common_inverse := reference_product.affine_inverse()
    for mesh_instance in meshes:
        var mesh := mesh_instance.mesh
        if mesh == null:
            continue
        for surface_idx in range(mesh.get_surface_count()):
            var arrays := mesh.surface_get_arrays(surface_idx)
            if arrays.is_empty():
                continue
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            if vertices.is_empty():
                continue
            if indices.is_empty():
                for i in range(0, vertices.size() - 2, 3):
                    max_edge_length_delta_m = maxf(max_edge_length_delta_m, _edge_delta(vertices[i], vertices[i + 1], common_inverse))
                    max_edge_length_delta_m = maxf(max_edge_length_delta_m, _edge_delta(vertices[i + 1], vertices[i + 2], common_inverse))
                    max_edge_length_delta_m = maxf(max_edge_length_delta_m, _edge_delta(vertices[i + 2], vertices[i], common_inverse))
                    edge_observations += 3
            else:
                for i in range(0, indices.size() - 2, 3):
                    var a := int(indices[i])
                    var b := int(indices[i + 1])
                    var c := int(indices[i + 2])
                    max_edge_length_delta_m = maxf(max_edge_length_delta_m, _edge_delta(vertices[a], vertices[b], common_inverse))
                    max_edge_length_delta_m = maxf(max_edge_length_delta_m, _edge_delta(vertices[b], vertices[c], common_inverse))
                    max_edge_length_delta_m = maxf(max_edge_length_delta_m, _edge_delta(vertices[c], vertices[a], common_inverse))
                    edge_observations += 3

    if edge_observations <= 0:
        _fail("no_triangle_edges_observed")
    if max_edge_length_delta_m > EDGE_LENGTH_EPS_M:
        _fail("common_origin_changed_edge_lengths")

    _finish({
        "format": "grand-bruxelles-gate8-bind-origin-edge-invariance-v1",
        "candidate_variant": 1,
        "target_bone_count": skeleton.get_bone_count(),
        "skinned_mesh_count": meshes.size(),
        "bind_observations": bind_observations,
        "reference_product_translation_m": reference_product.origin.length(),
        "max_product_translation_delta_m": max_translation_spread,
        "max_product_rotation_delta_deg": max_rotation_spread_deg,
        "edge_observations": edge_observations,
        "max_edge_length_delta_m": max_edge_length_delta_m,
        "edge_length_epsilon_m": EDGE_LENGTH_EPS_M,
        "diagnostic_state": "COMMON_BIND_ORIGIN_EDGE_INVARIANT",
        "retarget_applied": false,
        "target_skin_modified": false,
        "target_rest_modified": false,
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "failures": _failures,
    })

func _edge_delta(a: Vector3, b: Vector3, transform: Transform3D) -> float:
    var before := a.distance_to(b)
    var after := (transform * a).distance_to(transform * b)
    return absf(after - before)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _collect_skinned_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        if mi.skin != null and mi.mesh != null:
            out.append(mi)
    for child in node.get_children():
        _collect_skinned_meshes(child, out)

func _fail(message: String) -> void:
    if not _failures.has(message):
        _failures.append(message)

func _finish(result: Dictionary) -> void:
    if result.is_empty():
        result = {
            "format": "grand-bruxelles-gate8-bind-origin-edge-invariance-v1",
            "candidate_variant": 1,
            "diagnostic_state": "BLOCKED",
            "retarget_applied": false,
            "production_authorized": false,
            "activation_ready": false,
            "adoption_ready": false,
            "run_alias_selected": "",
            "failures": _failures,
        }
    var path := "gate8_variant01_bind_origin_edge_invariance_result.json"
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify(result, "  "))
    file.close()
    print("GATE8_BIND_ORIGIN_EDGE_INVARIANCE state=%s edges=%d max_delta_m=%.12f failures=%d" % [result.get("diagnostic_state", "BLOCKED"), int(result.get("edge_observations", 0)), float(result.get("max_edge_length_delta_m", -1.0)), _failures.size()])
    if _failures.is_empty():
        quit(0)
    for failure in _failures:
        push_error(failure)
    quit(1)
