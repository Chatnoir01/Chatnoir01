extends SceneTree

const TARGET_SCENE := "res://assets/npc_gate_06.glb"
const OUTPUT_PATH := "res://gate8_variant06_target_micropose_skin_result.json"
const EXPECTED_TARGET_BONES := 53
const EXPECTED_SKINNED_MESHES := 8
const EXPECTED_SKINNED_SURFACES := 8
const EXPECTED_MATERIAL_SURFACES := 8
const EXPECTED_VERTICES := 24073
const MICROPOSE_DEG := 5.0
const MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25
const MAX_EDGE_STRETCH_RATIO := 3.0
const MIN_EDGE_COMPRESSION_RATIO := 0.25
const MAX_FOOT_DRIFT_M := 0.000001
const MAX_REST_POSITION_DRIFT_M := 0.000001
const MAX_REST_ROTATION_DRIFT_DEG := 0.0001
const COMMON_TRANSLATION_EPS_M := 0.00001
const COMMON_ROTATION_EPS_DEG := 0.01

const TARGET_ROLE_MAP := {
    "hips": "pelvis", "spine": "spine_01", "chest": "spine_02", "upper_chest": "spine_03",
    "neck": "neck_01", "head": "head",
    "left_shoulder": "clavicle_l", "left_upper_arm": "upperarm_l", "left_forearm": "lowerarm_l", "left_hand": "hand_l",
    "right_shoulder": "clavicle_r", "right_upper_arm": "upperarm_r", "right_forearm": "lowerarm_r", "right_hand": "hand_r",
    "left_upper_leg": "thigh_l", "left_lower_leg": "calf_l", "left_foot": "foot_l", "left_toe": "ball_l",
    "right_upper_leg": "thigh_r", "right_lower_leg": "calf_r", "right_foot": "foot_r", "right_toe": "ball_r"
}
const MICROPOSE_ROLES := [
    "upper_chest",
    "left_shoulder", "left_upper_arm", "left_forearm", "left_hand",
    "right_shoulder", "right_upper_arm", "right_forearm", "right_hand"
]
const AXIS_NAMES := ["x", "y", "z"]
const AXIS_VECTORS := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]

var failures: Array[String] = []
var target: Skeleton3D
var target_roles: Dictionary = {}
var meshes: Array[MeshInstance3D] = []
var common_inverse := Transform3D.IDENTITY
var common_origin_translation_m := 0.0
var common_origin_rotation_deg := 0.0
var max_bind_translation_delta_m := 0.0
var max_bind_rotation_delta_deg := 0.0
var bind_observations := 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if not _synthetic_rigid_edge_regression():
        failures.append("synthetic_rigid_edge_regression_failed")
    var packed := load(TARGET_SCENE) as PackedScene
    if packed == null:
        _finish(_base_result("BLOCKED_TARGET_LOAD"))
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        failures.append("target_instance_failed")
        _finish(_base_result("BLOCKED_TARGET_INSTANCE"))
        return
    root.add_child(scene)
    await process_frame
    await process_frame
    target = _find_skeleton(scene)
    _collect_skinned_meshes(scene, meshes)
    if target == null:
        failures.append("target_skeleton_missing")
        _finish(_base_result("BLOCKED_TARGET_SKELETON"))
        return
    if target.get_bone_count() != EXPECTED_TARGET_BONES:
        failures.append("target_bone_count=%d" % target.get_bone_count())
    if meshes.size() != EXPECTED_SKINNED_MESHES:
        failures.append("target_skinned_mesh_count=%d" % meshes.size())
    target_roles = _resolve_target_roles()
    var inventory := _validate_skin_integrity()
    if not failures.is_empty():
        var blocked := _base_result("BLOCKED_TARGET_INTEGRITY")
        blocked["skin_inventory"] = inventory
        _finish(blocked)
        return

    var rest_snapshot := _capture_rest_snapshot()
    target.reset_bone_poses()
    target.force_update_all_bone_transforms()
    if not _ensure_common_bind_origin():
        _finish(_base_result("BLOCKED_BIND_ORIGIN"))
        return
    var rest_positions := _capture_skinned_positions()
    if rest_positions.is_empty():
        failures.append("rest_skin_positions_missing")
        _finish(_base_result("BLOCKED_REST_SKIN_CAPTURE"))
        return

    var left_foot_idx := int(target_roles["left_foot"])
    var right_foot_idx := int(target_roles["right_foot"])
    var left_foot_rest := target.get_bone_global_pose(left_foot_idx).origin
    var right_foot_rest := target.get_bone_global_pose(right_foot_idx).origin
    var rows: Array[Dictionary] = []
    var blocked_cases: Array[String] = []
    var max_edge_change := 0.0
    var max_stretch := 1.0
    var min_compression := 1.0
    var max_foot_drift := 0.0
    var worst_case := ""
    var worst_edge: Dictionary = {}
    var triangles_measured := 0

    for role_value in MICROPOSE_ROLES:
        var role := String(role_value)
        var bone_idx := int(target_roles[role])
        for axis_idx in range(AXIS_VECTORS.size()):
            var axis: Vector3 = AXIS_VECTORS[axis_idx]
            var axis_name := String(AXIS_NAMES[axis_idx])
            for sign_f in [-1.0, 1.0]:
                target.reset_bone_poses()
                target.set_bone_pose_rotation(bone_idx, Quaternion(axis, deg_to_rad(MICROPOSE_DEG * float(sign_f))))
                target.force_update_all_bone_transforms()
                var posed_positions := _capture_skinned_positions()
                var edge := _measure_edge_distortion(rest_positions, posed_positions)
                var edge_change := float(edge["max_edge_absolute_change_m"])
                var stretch := float(edge["max_edge_stretch_ratio"])
                var compression := float(edge["min_edge_compression_ratio"])
                triangles_measured = maxi(triangles_measured, int(edge["triangles_measured"]))
                var foot_drift := maxf(
                    left_foot_rest.distance_to(target.get_bone_global_pose(left_foot_idx).origin),
                    right_foot_rest.distance_to(target.get_bone_global_pose(right_foot_idx).origin)
                )
                max_foot_drift = maxf(max_foot_drift, foot_drift)
                var case_name := "%s_%s_%s5deg" % [role, axis_name, "minus" if float(sign_f) < 0.0 else "plus"]
                var within := edge_change <= MAX_EDGE_ABSOLUTE_CHANGE_M and stretch <= MAX_EDGE_STRETCH_RATIO and compression >= MIN_EDGE_COMPRESSION_RATIO and foot_drift <= MAX_FOOT_DRIFT_M
                if not within:
                    blocked_cases.append(case_name)
                if edge_change > max_edge_change:
                    max_edge_change = edge_change
                    worst_case = case_name
                    worst_edge = (edge["max_absolute_edge"] as Dictionary).duplicate(true)
                max_stretch = maxf(max_stretch, stretch)
                min_compression = minf(min_compression, compression)
                rows.append({
                    "case": case_name, "role": role, "bone": String(target.get_bone_name(bone_idx)),
                    "axis": axis_name, "degrees": MICROPOSE_DEG * float(sign_f),
                    "max_edge_absolute_change_m": edge_change, "max_edge_stretch_ratio": stretch,
                    "min_edge_compression_ratio": compression, "max_foot_drift_m": foot_drift,
                    "within_gates": within
                })

    target.reset_bone_poses()
    target.force_update_all_bone_transforms()
    var rest_drift := _validate_rest_snapshot(rest_snapshot)
    if max_foot_drift > MAX_FOOT_DRIFT_M:
        failures.append("arm_micropose_moved_feet=%.9f" % max_foot_drift)
    var structurally_valid := failures.is_empty()
    var microposes_green := structurally_valid and blocked_cases.is_empty()
    var state := "TARGET_MICROPOSE_SKIN_SANE" if microposes_green else ("TARGET_MICROPOSE_SKIN_BLOCKED" if structurally_valid else "BLOCKED_TARGET_MICROPOSE_INTEGRITY")
    var result := _base_result(state)
    result["engine_version"] = Engine.get_version_info().get("string", "unknown")
    result["target_bone_count"] = target.get_bone_count()
    result["reviewed_role_count"] = target_roles.size()
    result["skin_inventory"] = inventory
    result["micropose_degrees"] = MICROPOSE_DEG
    result["micropose_role_count"] = MICROPOSE_ROLES.size()
    result["axis_count"] = AXIS_VECTORS.size()
    result["case_count"] = rows.size()
    result["case_results"] = rows
    result["blocked_cases"] = blocked_cases
    result["blocked_case_count"] = blocked_cases.size()
    result["target_microposes_within_skin_gates"] = microposes_green
    result["triangles_measured_per_case"] = triangles_measured
    result["max_edge_absolute_change_m"] = max_edge_change
    result["max_edge_stretch_ratio"] = max_stretch
    result["min_edge_compression_ratio"] = min_compression
    result["max_foot_drift_m"] = max_foot_drift
    result["worst_case"] = worst_case
    result["worst_edge"] = worst_edge
    result["rest_drift"] = rest_drift
    result["common_bind_origin_translation_m"] = common_origin_translation_m
    result["common_bind_origin_rotation_deg"] = common_origin_rotation_deg
    result["max_bind_product_translation_delta_m"] = max_bind_translation_delta_m
    result["max_bind_product_rotation_delta_deg"] = max_bind_rotation_delta_deg
    result["bind_observations"] = bind_observations
    result["next_safe_axis"] = "SOURCE_TO_TARGET_POSE_AMPLITUDE_OR_REST_FRAME" if microposes_green else "REJECT_VARIANT06_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED"
    _finish(result)

func _base_result(state: String) -> Dictionary:
    return {
        "format":"grand-bruxelles-gate8-variant06-target-micropose-skin-v1",
        "candidate_variant":6,
        "measurement":"target_only_controlled_micropose_cpu_skin_space",
        "source_animation_used":false,"retarget_applied":false,"target_skin_modified":false,
        "target_rest_modified":false,"threshold_changed":false,
        "max_edge_absolute_change_allowed_m":MAX_EDGE_ABSOLUTE_CHANGE_M,
        "max_edge_stretch_allowed_ratio":MAX_EDGE_STRETCH_RATIO,
        "min_edge_compression_allowed_ratio":MIN_EDGE_COMPRESSION_RATIO,
        "max_foot_drift_allowed_m":MAX_FOOT_DRIFT_M,
        "diagnostic_state":state,"walk_alias_selected":"","run_alias_selected":"",
        "production_authorized":false,"activation_ready":false,"adoption_ready":false,
        "runtime_population_changed":false,"visual_witness_authorized":false,
        "visual_approval_claimed":false,"player_character_reuse_allowed":false,
        "mixamo_payload_allowed":false,"failures":failures
    }

func _resolve_target_roles() -> Dictionary:
    var result := {}
    var seen := {}
    for role_value in TARGET_ROLE_MAP.keys():
        var role := String(role_value)
        var bone_name := String(TARGET_ROLE_MAP[role])
        var idx := target.find_bone(bone_name)
        if idx < 0:
            failures.append("target_role_missing=%s:%s" % [role, bone_name])
        elif seen.has(idx):
            failures.append("target_role_duplicate_bone=%s:%s" % [role, bone_name])
        else:
            seen[idx] = role
            result[role] = idx
    if result.size() != TARGET_ROLE_MAP.size():
        failures.append("target_role_count=%d" % result.size())
    return result

func _validate_skin_integrity() -> Dictionary:
    var surfaces := 0
    var material_surfaces := 0
    var vertices := 0
    var invalid_links := 0
    for mi in meshes:
        if mi.get_node_or_null(mi.skeleton) != target:
            invalid_links += 1
            failures.append("invalid_skeleton_link=%s" % mi.name)
        if mi.mesh == null or mi.skin == null:
            failures.append("mesh_or_skin_missing=%s" % mi.name)
            continue
        for s in range(mi.mesh.get_surface_count()):
            if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            surfaces += 1
            if mi.get_active_material(s) != null:
                material_surfaces += 1
            else:
                failures.append("missing_material=%s:%d" % [mi.name, s])
            var arrays := mi.mesh.surface_get_arrays(s)
            var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            vertices += vv.size()
    if surfaces != EXPECTED_SKINNED_SURFACES: failures.append("skinned_surface_count=%d" % surfaces)
    if material_surfaces != EXPECTED_MATERIAL_SURFACES: failures.append("material_surface_count=%d" % material_surfaces)
    if vertices != EXPECTED_VERTICES: failures.append("vertex_count=%d" % vertices)
    return {"skinned_meshes":meshes.size(),"skinned_surfaces":surfaces,"material_surfaces":material_surfaces,"vertices":vertices,"invalid_skeleton_links":invalid_links}

func _capture_rest_snapshot() -> Array[Transform3D]:
    var out: Array[Transform3D] = []
    for i in range(target.get_bone_count()):
        out.append(target.get_bone_rest(i))
    return out

func _validate_rest_snapshot(snapshot: Array[Transform3D]) -> Dictionary:
    var max_pos := 0.0
    var max_rot := 0.0
    for i in range(target.get_bone_count()):
        max_pos = maxf(max_pos, snapshot[i].origin.distance_to(target.get_bone_rest(i).origin))
        max_rot = maxf(max_rot, _basis_delta_deg(snapshot[i].basis, target.get_bone_rest(i).basis))
    if max_pos > MAX_REST_POSITION_DRIFT_M: failures.append("rest_position_drift=%.9f" % max_pos)
    if max_rot > MAX_REST_ROTATION_DRIFT_DEG: failures.append("rest_rotation_drift=%.9f" % max_rot)
    return {"max_position_drift_m":max_pos,"max_rotation_drift_deg":max_rot}

func _capture_skinned_positions() -> Dictionary:
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
            var n := int(bb.size() / vv.size())
            var posed := PackedVector3Array()
            posed.resize(vv.size())
            for vi in range(vv.size()):
                posed[vi] = common_inverse * _skin_vertex(skin, vv[vi], bb, ww, vi, n)
            result[_surface_key(mi, s)] = posed
    return result

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
        out += (target.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_idx) * vertex) * w
        sum += w
    return vertex if sum <= 0.000001 else out / sum

func _measure_edge_distortion(rest_positions: Dictionary, posed_positions: Dictionary) -> Dictionary:
    var max_ratio := 1.0
    var min_ratio := 1.0
    var max_abs := 0.0
    var max_row := {}
    var triangles := 0
    for mi in meshes:
        for s in range(mi.mesh.get_surface_count()):
            if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            var key := _surface_key(mi, s)
            var arrays := mi.mesh.surface_get_arrays(s)
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            var rest: PackedVector3Array = rest_positions[key]
            var posed: PackedVector3Array = posed_positions[key]
            var count := int(indices.size() / 3) if not indices.is_empty() else int(rest.size() / 3)
            for tri in range(count):
                var ids := [
                    indices[tri*3] if not indices.is_empty() else tri*3,
                    indices[tri*3+1] if not indices.is_empty() else tri*3+1,
                    indices[tri*3+2] if not indices.is_empty() else tri*3+2
                ]
                triangles += 1
                for pair in [[0,1,"01"],[1,2,"12"],[2,0,"20"]]:
                    var a := int(ids[int(pair[0])])
                    var b := int(ids[int(pair[1])])
                    var rl := rest[a].distance_to(rest[b])
                    if rl <= 0.000001:
                        continue
                    var pl := posed[a].distance_to(posed[b])
                    var ratio := pl / rl
                    var change := absf(pl - rl)
                    max_ratio = maxf(max_ratio, ratio)
                    min_ratio = minf(min_ratio, ratio)
                    if change > max_abs:
                        max_abs = change
                        max_row = {"surface":key,"triangle":tri,"edge":String(pair[2]),"vertex_a":a,"vertex_b":b,"rest_length_m":rl,"posed_length_m":pl,"absolute_edge_length_change_m":change,"stretch_ratio":ratio}
    if triangles <= 0:
        failures.append("no_triangles_measured")
    return {"triangles_measured":triangles,"max_edge_stretch_ratio":max_ratio,"min_edge_compression_ratio":min_ratio,"max_edge_absolute_change_m":max_abs,"max_absolute_edge":max_row}

func _ensure_common_bind_origin() -> bool:
    var reference := Transform3D.IDENTITY
    var have := false
    for mi in meshes:
        var skin: Skin = mi.skin
        for bind_idx in range(skin.get_bind_count()):
            var bone_idx := _resolve_skin_bone(skin, bind_idx)
            if bone_idx < 0:
                failures.append("normalized_bind_unresolved=%d" % bind_idx)
                continue
            var product := target.get_bone_global_rest(bone_idx) * skin.get_bind_pose(bind_idx)
            if not have:
                reference = product
                have = true
            else:
                max_bind_translation_delta_m = maxf(max_bind_translation_delta_m, reference.origin.distance_to(product.origin))
                max_bind_rotation_delta_deg = maxf(max_bind_rotation_delta_deg, _basis_delta_deg(reference.basis, product.basis))
            bind_observations += 1
    if not have:
        failures.append("common_bind_origin_missing")
        return false
    common_origin_translation_m = reference.origin.length()
    common_origin_rotation_deg = _basis_delta_deg(Basis.IDENTITY, reference.basis)
    if max_bind_translation_delta_m > COMMON_TRANSLATION_EPS_M:
        failures.append("common_bind_translation_spread=%.9f" % max_bind_translation_delta_m)
    if max_bind_rotation_delta_deg > COMMON_ROTATION_EPS_DEG:
        failures.append("common_bind_rotation_spread=%.9f" % max_bind_rotation_delta_deg)
    common_inverse = reference.affine_inverse()
    return failures.is_empty()

func _resolve_skin_bone(skin: Skin, bind_idx: int) -> int:
    var name := String(skin.get_bind_name(bind_idx))
    return target.find_bone(name) if not name.is_empty() else skin.get_bind_bone(bind_idx)

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

func _synthetic_rigid_edge_regression() -> bool:
    var p := [Vector3.ZERO, Vector3(0.3,0.1,-0.2), Vector3(-0.1,0.4,0.25)]
    var t := Transform3D(Basis(Quaternion(Vector3(0.3,0.7,0.2).normalized(), deg_to_rad(37.0))), Vector3(2,-1,0.5))
    for pair in [[0,1],[1,2],[2,0]]:
        var before: float = p[int(pair[0])].distance_to(p[int(pair[1])])
        var after: float = (t * p[int(pair[0])]).distance_to(t * p[int(pair[1])])
        if absf(before - after) > 0.00001:
            return false
    return true

func _finish(result: Dictionary) -> void:
    result["failures"] = failures
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        push_error("result_file_open_failed")
        quit(1)
        return
    file.store_string(JSON.stringify(result, "\t"))
    file.close()
    if not failures.is_empty():
        for failure in failures:
            push_error(failure)
        print("GATE8_VARIANT06_TARGET_MICROPOSE_BLOCKED state=%s failures=%d" % [String(result.get("diagnostic_state","unknown")), failures.size()])
        quit(1)
        return
    print("GATE8_VARIANT06_TARGET_MICROPOSE state=%s cases=%d blocked=%d edge=%.9f stretch=%.9f compression=%.9f" % [String(result.get("diagnostic_state","unknown")),int(result.get("case_count",0)),int(result.get("blocked_case_count",0)),float(result.get("max_edge_absolute_change_m",0.0)),float(result.get("max_edge_stretch_ratio",1.0)),float(result.get("min_edge_compression_ratio",1.0))])
    quit(0)
