extends SceneTree

const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const OUTPUT_PATH := "res://gate8_engine_skin_parity_result.json"
const EXPECTED_BONES := 53
const EXPECTED_MESHES := 8
const EXPECTED_VERTICES := 21044
const TEST_BONE := "clavicle_r"
const TEST_AXIS := Vector3.BACK
const TEST_DEGREES := -5.0
const MAX_VERTEX_ERROR_M := 0.0001
const COMMON_TRANSLATION_EPS_M := 0.00001
const COMMON_ROTATION_EPS_DEG := 0.01

var failures: Array[String] = []
var skeleton: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var common_inverse := Transform3D.IDENTITY

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load(TARGET_SCENE) as PackedScene
    if packed == null:
        failures.append("target_load_failed")
        _finish({"diagnostic_state":"BLOCKED_TARGET_LOAD"})
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        failures.append("target_instance_failed")
        _finish({"diagnostic_state":"BLOCKED_TARGET_INSTANCE"})
        return
    root.add_child(scene)
    await process_frame
    await process_frame
    skeleton = _find_skeleton(scene)
    _collect_skinned_meshes(scene, meshes)
    if skeleton == null:
        failures.append("skeleton_missing")
        _finish({"diagnostic_state":"BLOCKED_SKELETON"})
        return
    if skeleton.get_bone_count() != EXPECTED_BONES:
        failures.append("bone_count=%d" % skeleton.get_bone_count())
    if meshes.size() != EXPECTED_MESHES:
        failures.append("mesh_count=%d" % meshes.size())
    var vertex_count := 0
    for mi in meshes:
        for s in range(mi.mesh.get_surface_count()):
            if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            var arrays := mi.mesh.surface_get_arrays(s)
            var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            vertex_count += vv.size()
    if vertex_count != EXPECTED_VERTICES:
        failures.append("vertex_count=%d" % vertex_count)
    if not _ensure_common_bind_origin():
        _finish({"diagnostic_state":"BLOCKED_BIND_ORIGIN","vertex_count":vertex_count})
        return

    skeleton.reset_bone_poses()
    skeleton.force_update_all_bone_transforms()
    await process_frame
    await process_frame
    var rest_cpu := _capture_cpu_positions()
    var rest_engine := _capture_engine_baked_positions()
    var rest_parity := _compare_position_sets(rest_cpu, rest_engine)

    var bone_idx := skeleton.find_bone(TEST_BONE)
    if bone_idx < 0:
        failures.append("test_bone_missing=%s" % TEST_BONE)
        _finish({"diagnostic_state":"BLOCKED_TEST_BONE","rest_parity":rest_parity})
        return
    skeleton.set_bone_pose_rotation(bone_idx, Quaternion(TEST_AXIS, deg_to_rad(TEST_DEGREES)))
    skeleton.force_update_all_bone_transforms()
    await process_frame
    await process_frame
    var pose_cpu := _capture_cpu_positions()
    var pose_engine := _capture_engine_baked_positions()
    var pose_parity := _compare_position_sets(pose_cpu, pose_engine)

    skeleton.reset_bone_poses()
    skeleton.force_update_all_bone_transforms()

    var rest_ok := bool(rest_parity.get("comparable", false)) and float(rest_parity.get("max_vertex_error_m", INF)) <= MAX_VERTEX_ERROR_M
    var pose_ok := bool(pose_parity.get("comparable", false)) and float(pose_parity.get("max_vertex_error_m", INF)) <= MAX_VERTEX_ERROR_M
    var parity_ok := rest_ok and pose_ok and failures.is_empty()
    var result := {
        "format":"grand-bruxelles-gate8-engine-skin-parity-result-v1",
        "diagnostic_state":"CPU_ENGINE_SKIN_PARITY_CONFIRMED" if parity_ok else "CPU_ENGINE_SKIN_PARITY_BLOCKED",
        "engine_version":Engine.get_version_info().get("string","unknown"),
        "candidate_variant":1,
        "measurement":"cpu_skin_formula_vs_bake_mesh_from_current_skeleton_pose",
        "test_bone":TEST_BONE,
        "test_axis":"z",
        "test_degrees":TEST_DEGREES,
        "max_vertex_parity_error_allowed_m":MAX_VERTEX_ERROR_M,
        "rest_parity":rest_parity,
        "pose_parity":pose_parity,
        "target_bone_count":skeleton.get_bone_count(),
        "skinned_mesh_count":meshes.size(),
        "vertex_count":vertex_count,
        "source_animation_used":false,
        "retarget_applied":false,
        "target_skin_modified":false,
        "target_rest_modified":false,
        "production_authorized":false,
        "activation_ready":false,
        "adoption_ready":false,
        "visual_witness_authorized":false,
        "next_safe_axis":"ISOLATED_REWEIGHT_AB" if parity_ok else "FIX_CPU_SKIN_HARNESS_BEFORE_REWEIGHT"
    }
    _finish(result)

func _capture_cpu_positions() -> Dictionary:
    var result := {}
    for mi in meshes:
        var skin: Skin = mi.skin
        for s in range(mi.mesh.get_surface_count()):
            if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            var arrays := mi.mesh.surface_get_arrays(s)
            var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var bb = arrays[Mesh.ARRAY_BONES]
            var ww = arrays[Mesh.ARRAY_WEIGHTS]
            if vv.is_empty() or bb.size() != ww.size() or bb.size() % vv.size() != 0:
                failures.append("skin_array_shape_invalid=%s:%d" % [mi.name, s])
                continue
            var influence_count := int(bb.size() / vv.size())
            var posed := PackedVector3Array()
            posed.resize(vv.size())
            for vi in range(vv.size()):
                posed[vi] = common_inverse * _skin_vertex(skin, vv[vi], bb, ww, vi, influence_count)
            result[_surface_key(mi, s)] = posed
    return result

func _capture_engine_baked_positions() -> Dictionary:
    var result := {}
    for mi in meshes:
        var baked := mi.bake_mesh_from_current_skeleton_pose()
        if baked == null:
            failures.append("engine_bake_failed=%s" % mi.name)
            continue
        if baked.get_surface_count() != mi.mesh.get_surface_count():
            failures.append("engine_bake_surface_count=%s:%d" % [mi.name, baked.get_surface_count()])
            continue
        for s in range(baked.get_surface_count()):
            if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            var arrays := baked.surface_get_arrays(s)
            var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            result[_surface_key(mi, s)] = vv
    return result

func _compare_position_sets(cpu: Dictionary, engine: Dictionary) -> Dictionary:
    var max_error := 0.0
    var sum_error := 0.0
    var compared := 0
    var worst := {}
    var keys := cpu.keys()
    keys.sort()
    for key_value in keys:
        var key := String(key_value)
        if not engine.has(key):
            failures.append("engine_surface_missing=%s" % key)
            continue
        var a: PackedVector3Array = cpu[key]
        var b: PackedVector3Array = engine[key]
        if a.size() != b.size():
            failures.append("parity_vertex_count=%s:%d:%d" % [key,a.size(),b.size()])
            continue
        for i in range(a.size()):
            var error := a[i].distance_to(b[i])
            sum_error += error
            compared += 1
            if error > max_error:
                max_error = error
                worst = {"surface":key,"vertex":i,"cpu":_vec(a[i]),"engine":_vec(b[i]),"error_m":error}
    return {
        "comparable": compared == EXPECTED_VERTICES,
        "vertices_compared": compared,
        "max_vertex_error_m": max_error,
        "mean_vertex_error_m": (sum_error / float(compared)) if compared > 0 else INF,
        "worst_vertex": worst
    }

func _skin_vertex(skin: Skin, vertex: Vector3, bones, weights, vi: int, n: int) -> Vector3:
    var out := Vector3.ZERO
    var sum := 0.0
    for j in range(n):
        var off := vi * n + j
        var w := float(weights[off])
        if w <= 0.0:
            continue
        var bind_idx := int(bones[off])
        if bind_idx < 0 or bind_idx >= skin.get_bind_count():
            failures.append("bind_index_out_of_range=%d" % bind_idx)
            continue
        var bone_idx := _resolve_skin_bone(skin, bind_idx)
        if bone_idx < 0:
            failures.append("skin_bind_unresolved=%d" % bind_idx)
            continue
        out += (skeleton.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_idx) * vertex) * w
        sum += w
    return vertex if sum <= 0.000001 else out / sum

func _ensure_common_bind_origin() -> bool:
    var reference := Transform3D.IDENTITY
    var have := false
    var max_translation := 0.0
    var max_rotation := 0.0
    for mi in meshes:
        var skin: Skin = mi.skin
        if skin == null:
            failures.append("skin_missing=%s" % mi.name)
            continue
        for bind_idx in range(skin.get_bind_count()):
            var bone_idx := _resolve_skin_bone(skin, bind_idx)
            if bone_idx < 0:
                failures.append("bind_unresolved=%d" % bind_idx)
                continue
            var product := skeleton.get_bone_global_rest(bone_idx) * skin.get_bind_pose(bind_idx)
            if not have:
                reference = product
                have = true
            else:
                max_translation = maxf(max_translation, reference.origin.distance_to(product.origin))
                max_rotation = maxf(max_rotation, _basis_delta_deg(reference.basis, product.basis))
    if not have:
        failures.append("common_bind_origin_missing")
        return false
    if max_translation > COMMON_TRANSLATION_EPS_M:
        failures.append("common_bind_translation_spread=%.9f" % max_translation)
    if max_rotation > COMMON_ROTATION_EPS_DEG:
        failures.append("common_bind_rotation_spread=%.9f" % max_rotation)
    common_inverse = reference.affine_inverse()
    return failures.is_empty()

func _resolve_skin_bone(skin: Skin, bind_idx: int) -> int:
    var name := String(skin.get_bind_name(bind_idx))
    return skeleton.find_bone(name) if not name.is_empty() else skin.get_bind_bone(bind_idx)

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
        if mi.mesh != null and mi.skin != null:
            out.append(mi)
    for child in node.get_children():
        _collect_skinned_meshes(child, out)

func _surface_key(mi: MeshInstance3D, surface_idx: int) -> String:
    return "%s#%d" % [String(mi.get_path()), surface_idx]

func _basis_delta_deg(a: Basis, b: Basis) -> float:
    var qa := a.orthonormalized().get_rotation_quaternion().normalized()
    var qb := b.orthonormalized().get_rotation_quaternion().normalized()
    var d := (qa.inverse() * qb).normalized()
    return rad_to_deg(2.0 * atan2(Vector3(d.x,d.y,d.z).length(), absf(d.w)))

func _vec(v: Vector3) -> Array[float]:
    return [v.x,v.y,v.z]

func _finish(result: Dictionary) -> void:
    result["failures"] = failures
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        push_error("result_file_open_failed")
        quit(1)
        return
    file.store_string(JSON.stringify(result, "\t"))
    file.close()
    print("GATE8_ENGINE_SKIN_PARITY state=%s failures=%d" % [String(result.get("diagnostic_state","unknown")),failures.size()])
    quit(0 if failures.is_empty() else 1)
