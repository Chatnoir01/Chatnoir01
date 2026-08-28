extends SceneTree

const TARGET_SCENE := "res://assets/npc_gate_03.glb"
const OUTPUT_PATH := "res://gate8_variant03_target_micropose_skin_result.json"
const EXPECTED_TARGET_BONES := 53
const EXPECTED_SKINNED_MESHES := 8
const EXPECTED_SKINNED_SURFACES := 8
const EXPECTED_MATERIAL_SURFACES := 8
const EXPECTED_VERTICES := 20495
const MICROPOSE_DEG := 5.0
const MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25
const MAX_EDGE_STRETCH_RATIO := 3.0
const MIN_EDGE_COMPRESSION_RATIO := 0.25
const MAX_FOOT_DRIFT_M := 0.000001
const COMMON_TRANSLATION_EPS_M := 0.00001
const COMMON_ROTATION_EPS_DEG := 0.01
const MAX_REST_POSITION_DRIFT_M := 0.000001
const MAX_REST_ROTATION_DRIFT_DEG := 0.0001
const BASELINE_EDGE_EPS_M := 0.000001

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

var _failures: Array[String] = []
var _target: Skeleton3D
var _target_roles: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []
var _common_inverse := Transform3D.IDENTITY
var _common_ready := false
var _common_origin_translation_m := 0.0
var _common_origin_rotation_deg := 0.0
var _max_product_translation_delta_m := 0.0
var _max_product_rotation_delta_deg := 0.0
var _bind_observations := 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if not _synthetic_rigid_edge_regression():
        _failures.append("synthetic_rigid_edge_regression_failed")

    var target_packed: PackedScene = load(TARGET_SCENE) as PackedScene
    if target_packed == null:
        _finish(_base_result("BLOCKED_TARGET_LOAD"))
        return
    var target_scene: Node3D = target_packed.instantiate() as Node3D
    if target_scene == null:
        _failures.append("target_instance_failed")
        _finish(_base_result("BLOCKED_TARGET_INSTANCE"))
        return
    root.add_child(target_scene)
    await process_frame
    await process_frame

    _target = _find_skeleton(target_scene)
    _collect_skinned_meshes(target_scene, _meshes)
    if _target == null:
        _failures.append("target_skeleton_missing")
        _finish(_base_result("BLOCKED_TARGET_SKELETON"))
        return
    if _target.get_bone_count() != EXPECTED_TARGET_BONES:
        _failures.append("target_bone_count=%d" % _target.get_bone_count())
    if _meshes.size() != EXPECTED_SKINNED_MESHES:
        _failures.append("target_skinned_mesh_count=%d" % _meshes.size())

    _target_roles = _resolve_target_roles()
    var skin_inventory: Dictionary = _validate_skin_integrity()
    if not _failures.is_empty():
        var blocked: Dictionary = _base_result("BLOCKED_TARGET_INTEGRITY")
        blocked["skin_inventory"] = skin_inventory
        _finish(blocked)
        return

    var rest_snapshot: Array[Transform3D] = _capture_rest_snapshot()
    _target.reset_bone_poses()
    _target.force_update_all_bone_transforms()
    if not _ensure_common_bind_origin():
        _finish(_base_result("BLOCKED_BIND_ORIGIN"))
        return
    var rest_positions: Dictionary = _capture_skinned_positions()
    if rest_positions.is_empty():
        _failures.append("rest_skin_positions_missing")
        _finish(_base_result("BLOCKED_REST_SKIN_CAPTURE"))
        return

    var baseline: Dictionary = _measure_edge_distortion(rest_positions, rest_positions)
    if float(baseline.get("max_edge_absolute_change_m", 1.0)) > BASELINE_EDGE_EPS_M:
        _failures.append("baseline_edge_change=%.9f" % float(baseline.get("max_edge_absolute_change_m", 1.0)))
    if absf(float(baseline.get("max_edge_stretch_ratio", 0.0)) - 1.0) > 0.000001:
        _failures.append("baseline_stretch_ratio=%.9f" % float(baseline.get("max_edge_stretch_ratio", 0.0)))
    if absf(float(baseline.get("min_edge_compression_ratio", 0.0)) - 1.0) > 0.000001:
        _failures.append("baseline_compression_ratio=%.9f" % float(baseline.get("min_edge_compression_ratio", 0.0)))

    var left_foot_idx: int = int(_target_roles["left_foot"])
    var right_foot_idx: int = int(_target_roles["right_foot"])
    var baseline_left_foot: Vector3 = _target.get_bone_global_pose(left_foot_idx).origin
    var baseline_right_foot: Vector3 = _target.get_bone_global_pose(right_foot_idx).origin

    var case_rows: Array[Dictionary] = []
    var blocked_cases: Array[String] = []
    var max_edge_change := 0.0
    var max_stretch := 1.0
    var min_compression := 1.0
    var max_foot_drift := 0.0
    var worst_case := ""
    var worst_edge: Dictionary = {}
    var triangles_measured := 0

    for role_value: Variant in MICROPOSE_ROLES:
        var role := String(role_value)
        var bone_idx := int(_target_roles[role])
        for axis_idx: int in range(AXIS_VECTORS.size()):
            var axis_name := String(AXIS_NAMES[axis_idx])
            var axis: Vector3 = AXIS_VECTORS[axis_idx]
            for sign_f: float in [-1.0, 1.0]:
                _target.reset_bone_poses()
                _target.set_bone_pose_rotation(bone_idx, Quaternion(axis, deg_to_rad(MICROPOSE_DEG * sign_f)))
                _target.force_update_all_bone_transforms()
                var posed_positions: Dictionary = _capture_skinned_positions()
                var edge_row: Dictionary = _measure_edge_distortion(rest_positions, posed_positions)
                var edge_change := float(edge_row.get("max_edge_absolute_change_m", 0.0))
                var stretch := float(edge_row.get("max_edge_stretch_ratio", 1.0))
                var compression := float(edge_row.get("min_edge_compression_ratio", 1.0))
                triangles_measured = maxi(triangles_measured, int(edge_row.get("triangles_measured", 0)))
                var left_drift := baseline_left_foot.distance_to(_target.get_bone_global_pose(left_foot_idx).origin)
                var right_drift := baseline_right_foot.distance_to(_target.get_bone_global_pose(right_foot_idx).origin)
                var foot_drift := maxf(left_drift, right_drift)
                max_foot_drift = maxf(max_foot_drift, foot_drift)
                var sign_name := "minus" if sign_f < 0.0 else "plus"
                var case_name := "%s_%s_%s5deg" % [role, axis_name, sign_name]
                var case_green := edge_change <= MAX_EDGE_ABSOLUTE_CHANGE_M and stretch <= MAX_EDGE_STRETCH_RATIO and compression >= MIN_EDGE_COMPRESSION_RATIO and foot_drift <= MAX_FOOT_DRIFT_M
                if not case_green:
                    blocked_cases.append(case_name)
                if edge_change > max_edge_change:
                    max_edge_change = edge_change
                    worst_case = case_name
                    worst_edge = edge_row.get("max_absolute_edge", {}).duplicate(true)
                max_stretch = maxf(max_stretch, stretch)
                min_compression = minf(min_compression, compression)
                case_rows.append({
                    "case": case_name,
                    "role": role,
                    "bone": String(_target.get_bone_name(bone_idx)),
                    "axis": axis_name,
                    "degrees": MICROPOSE_DEG * sign_f,
                    "max_edge_absolute_change_m": edge_change,
                    "max_edge_stretch_ratio": stretch,
                    "min_edge_compression_ratio": compression,
                    "max_foot_drift_m": foot_drift,
                    "within_gates": case_green
                })

    _target.reset_bone_poses()
    _target.force_update_all_bone_transforms()
    var rest_drift: Dictionary = _validate_rest_snapshot(rest_snapshot)
    if max_foot_drift > MAX_FOOT_DRIFT_M:
        _failures.append("arm_micropose_moved_feet=%.9f" % max_foot_drift)

    var structurally_valid := _failures.is_empty()
    var microposes_green := structurally_valid and blocked_cases.is_empty()
    var state := "TARGET_MICROPOSE_SKIN_SANE" if microposes_green else ("TARGET_MICROPOSE_SKIN_BLOCKED" if structurally_valid else "BLOCKED_TARGET_MICROPOSE_INTEGRITY")
    var result: Dictionary = _base_result(state)
    result["engine_version"] = Engine.get_version_info().get("string", "unknown")
    result["target_bone_count"] = _target.get_bone_count()
    result["reviewed_role_count"] = _target_roles.size()
    result["skin_inventory"] = skin_inventory
    result["micropose_degrees"] = MICROPOSE_DEG
    result["micropose_role_count"] = MICROPOSE_ROLES.size()
    result["axis_count"] = AXIS_VECTORS.size()
    result["case_count"] = case_rows.size()
    result["case_results"] = case_rows
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
    result["common_bind_origin_translation_m"] = _common_origin_translation_m
    result["common_bind_origin_rotation_deg"] = _common_origin_rotation_deg
    result["max_bind_product_translation_delta_m"] = _max_product_translation_delta_m
    result["max_bind_product_rotation_delta_deg"] = _max_product_rotation_delta_deg
    result["bind_observations"] = _bind_observations
    result["next_safe_axis"] = "SOURCE_TO_TARGET_POSE_AMPLITUDE_OR_REST_FRAME" if microposes_green else "REJECT_VARIANT03_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED"
    _finish(result)

func _base_result(state: String) -> Dictionary:
    return {
        "format": "grand-bruxelles-gate8-variant03-target-micropose-skin-v1",
        "candidate_variant": 3,
        "measurement": "target_only_controlled_micropose_cpu_skin_space",
        "source_animation_used": false,
        "retarget_applied": false,
        "target_skin_modified": false,
        "target_rest_modified": false,
        "threshold_changed": false,
        "max_edge_absolute_change_allowed_m": MAX_EDGE_ABSOLUTE_CHANGE_M,
        "max_edge_stretch_allowed_ratio": MAX_EDGE_STRETCH_RATIO,
        "min_edge_compression_allowed_ratio": MIN_EDGE_COMPRESSION_RATIO,
        "max_foot_drift_allowed_m": MAX_FOOT_DRIFT_M,
        "diagnostic_state": state,
        "walk_alias_selected": "",
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_witness_authorized": false,
        "visual_approval_claimed": false,
        "player_character_reuse_allowed": false,
        "mixamo_payload_allowed": false,
        "failures": _failures
    }

func _resolve_target_roles() -> Dictionary:
    var result: Dictionary = {}
    var seen: Dictionary = {}
    for role_value: Variant in TARGET_ROLE_MAP.keys():
        var role := String(role_value)
        var bone_name := String(TARGET_ROLE_MAP[role])
        var idx := _target.find_bone(bone_name)
        if idx < 0:
            _failures.append("target_role_missing=%s:%s" % [role, bone_name])
            continue
        if seen.has(idx):
            _failures.append("target_role_duplicate_bone=%s:%s" % [role, bone_name])
            continue
        seen[idx] = role
        result[role] = idx
    if result.size() != TARGET_ROLE_MAP.size():
        _failures.append("target_role_count=%d" % result.size())
    return result

func _validate_skin_integrity() -> Dictionary:
    var surfaces := 0
    var material_surfaces := 0
    var vertices := 0
    var invalid_skeleton_links := 0
    for mesh_instance: MeshInstance3D in _meshes:
        var resolved_skeleton := mesh_instance.get_node_or_null(mesh_instance.skeleton) as Skeleton3D
        if resolved_skeleton != _target:
            invalid_skeleton_links += 1
            _failures.append("invalid_skeleton_link=%s" % mesh_instance.name)
        var mesh: Mesh = mesh_instance.mesh
        if mesh == null or mesh_instance.skin == null:
            _failures.append("mesh_or_skin_missing=%s" % mesh_instance.name)
            continue
        for surface_idx: int in range(mesh.get_surface_count()):
            if mesh.surface_get_primitive_type(surface_idx) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            surfaces += 1
            if mesh_instance.get_active_material(surface_idx) != null:
                material_surfaces += 1
            else:
                _failures.append("missing_material=%s:%d" % [mesh_instance.name, surface_idx])
            var arrays: Array = mesh.surface_get_arrays(surface_idx)
            if arrays.size() <= Mesh.ARRAY_WEIGHTS:
                _failures.append("surface_arrays_incomplete=%s:%d" % [mesh_instance.name, surface_idx])
                continue
            var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            vertices += surface_vertices.size()
            if surface_vertices.is_empty():
                _failures.append("surface_vertices_empty=%s:%d" % [mesh_instance.name, surface_idx])
    if surfaces != EXPECTED_SKINNED_SURFACES:
        _failures.append("skinned_surface_count=%d" % surfaces)
    if material_surfaces != EXPECTED_MATERIAL_SURFACES:
        _failures.append("material_surface_count=%d" % material_surfaces)
    if vertices != EXPECTED_VERTICES:
        _failures.append("vertex_count=%d" % vertices)
    return {"skinned_meshes": _meshes.size(), "skinned_surfaces": surfaces, "material_surfaces": material_surfaces, "vertices": vertices, "invalid_skeleton_links": invalid_skeleton_links}

func _capture_rest_snapshot() -> Array[Transform3D]:
    var rows: Array[Transform3D] = []
    for bone_idx: int in range(_target.get_bone_count()):
        rows.append(_target.get_bone_rest(bone_idx))
    return rows

func _validate_rest_snapshot(snapshot: Array[Transform3D]) -> Dictionary:
    var max_pos := 0.0
    var max_rot := 0.0
    var worst_pos_bone := ""
    var worst_rot_bone := ""
    if snapshot.size() != _target.get_bone_count():
        _failures.append("rest_snapshot_count_mismatch")
        return {"max_position_drift_m": 1.0, "max_rotation_drift_deg": 360.0}
    for bone_idx: int in range(_target.get_bone_count()):
        var before: Transform3D = snapshot[bone_idx]
        var after: Transform3D = _target.get_bone_rest(bone_idx)
        var pos := before.origin.distance_to(after.origin)
        var rot := _basis_delta_deg(before.basis, after.basis)
        if pos > max_pos:
            max_pos = pos
            worst_pos_bone = String(_target.get_bone_name(bone_idx))
        if rot > max_rot:
            max_rot = rot
            worst_rot_bone = String(_target.get_bone_name(bone_idx))
    if max_pos > MAX_REST_POSITION_DRIFT_M:
        _failures.append("rest_position_drift=%.9f" % max_pos)
    if max_rot > MAX_REST_ROTATION_DRIFT_DEG:
        _failures.append("rest_rotation_drift=%.9f" % max_rot)
    return {"max_position_drift_m": max_pos, "max_rotation_drift_deg": max_rot, "worst_position_bone": worst_pos_bone, "worst_rotation_bone": worst_rot_bone}

func _capture_skinned_positions() -> Dictionary:
    var result: Dictionary = {}
    for mesh_instance: MeshInstance3D in _meshes:
        var mesh: Mesh = mesh_instance.mesh
        var skin: Skin = mesh_instance.skin
        if mesh == null or skin == null:
            continue
        for surface_idx: int in range(mesh.get_surface_count()):
            if mesh.surface_get_primitive_type(surface_idx) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            var arrays: Array = mesh.surface_get_arrays(surface_idx)
            if arrays.size() <= Mesh.ARRAY_WEIGHTS:
                continue
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var bones: Variant = arrays[Mesh.ARRAY_BONES]
            var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
            if vertices.is_empty() or bones.size() != weights.size() or bones.size() % vertices.size() != 0:
                _failures.append("skin_array_shape_invalid=%s:%d" % [mesh_instance.name, surface_idx])
                continue
            var influences_per_vertex: int = int(bones.size() / vertices.size())
            if influences_per_vertex <= 0:
                _failures.append("influence_count_invalid=%s:%d" % [mesh_instance.name, surface_idx])
                continue
            var transformed := PackedVector3Array()
            transformed.resize(vertices.size())
            for vertex_idx: int in range(vertices.size()):
                transformed[vertex_idx] = _common_inverse * _skin_vertex(skin, vertices[vertex_idx], bones, weights, vertex_idx, influences_per_vertex)
            result[_surface_key(mesh_instance, surface_idx)] = transformed
    return result

func _skin_vertex(skin: Skin, vertex: Vector3, bones: Variant, weights: Variant, vertex_idx: int, influences_per_vertex: int) -> Vector3:
    var out := Vector3.ZERO
    var weight_sum := 0.0
    for influence_idx: int in range(influences_per_vertex):
        var offset := vertex_idx * influences_per_vertex + influence_idx
        var weight := float(weights[offset])
        if weight <= 0.0:
            continue
        var bind_idx := int(bones[offset])
        if bind_idx < 0 or bind_idx >= skin.get_bind_count():
            _failures.append("bind_index_out_of_range=%d" % bind_idx)
            continue
        var bone_idx := _resolve_skin_bone(skin, bind_idx)
        if bone_idx < 0:
            _failures.append("skin_bind_unresolved=%d" % bind_idx)
            continue
        var skin_transform := _target.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_idx)
        out += (skin_transform * vertex) * weight
        weight_sum += weight
    return vertex if weight_sum <= 0.000001 else out / weight_sum

func _measure_edge_distortion(rest_positions: Dictionary, posed_positions: Dictionary) -> Dictionary:
    var max_ratio := 1.0
    var min_ratio := 1.0
    var max_abs_change := 0.0
    var max_abs_row: Dictionary = {}
    var triangles_measured := 0
    for mesh_instance: MeshInstance3D in _meshes:
        var mesh: Mesh = mesh_instance.mesh
        for surface_idx: int in range(mesh.get_surface_count()):
            if mesh.surface_get_primitive_type(surface_idx) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            var key := _surface_key(mesh_instance, surface_idx)
            if not rest_positions.has(key) or not posed_positions.has(key):
                continue
            var arrays: Array = mesh.surface_get_arrays(surface_idx)
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            var rest: PackedVector3Array = rest_positions[key]
            var posed: PackedVector3Array = posed_positions[key]
            var triangle_count: int = int(indices.size() / 3) if not indices.is_empty() else int(rest.size() / 3)
            for tri_idx: int in range(triangle_count):
                var ids := PackedInt32Array([0, 0, 0])
                for corner: int in range(3):
                    ids[corner] = indices[tri_idx * 3 + corner] if not indices.is_empty() else tri_idx * 3 + corner
                if ids[0] >= rest.size() or ids[1] >= rest.size() or ids[2] >= rest.size():
                    _failures.append("triangle_index_out_of_range=%s:%d:%d" % [mesh_instance.name, surface_idx, tri_idx])
                    continue
                triangles_measured += 1
                for pair: Array in [[0, 1, "01"], [1, 2, "12"], [2, 0, "20"]]:
                    var a := int(ids[int(pair[0])])
                    var b := int(ids[int(pair[1])])
                    var rest_len := rest[a].distance_to(rest[b])
                    if rest_len <= 0.000001:
                        continue
                    var posed_len := posed[a].distance_to(posed[b])
                    var ratio := posed_len / rest_len
                    var abs_change := absf(posed_len - rest_len)
                    max_ratio = maxf(max_ratio, ratio)
                    min_ratio = minf(min_ratio, ratio)
                    if abs_change > max_abs_change:
                        max_abs_change = abs_change
                        max_abs_row = {"surface": key, "surface_index": surface_idx, "triangle": tri_idx, "edge": String(pair[2]), "vertex_a": a, "vertex_b": b, "rest_length_m": rest_len, "posed_length_m": posed_len, "absolute_edge_length_change_m": abs_change, "stretch_ratio": ratio}
    if triangles_measured <= 0:
        _failures.append("no_triangles_measured")
    return {"triangles_measured": triangles_measured, "max_edge_stretch_ratio": max_ratio, "min_edge_compression_ratio": min_ratio, "max_edge_absolute_change_m": max_abs_change, "max_absolute_edge": max_abs_row}

func _ensure_common_bind_origin() -> bool:
    if _common_ready:
        return true
    var reference := Transform3D.IDENTITY
    var have_reference := false
    for mesh_instance: MeshInstance3D in _meshes:
        var skin: Skin = mesh_instance.skin
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
        _failures.append("common_bind_origin_missing")
        return false
    _common_origin_translation_m = reference.origin.length()
    _common_origin_rotation_deg = _basis_delta_deg(Basis.IDENTITY, reference.basis)
    if _max_product_translation_delta_m > COMMON_TRANSLATION_EPS_M:
        _failures.append("common_bind_translation_spread=%.9f" % _max_product_translation_delta_m)
    if _max_product_rotation_delta_deg > COMMON_ROTATION_EPS_DEG:
        _failures.append("common_bind_rotation_spread=%.9f" % _max_product_rotation_delta_deg)
    _common_inverse = reference.affine_inverse()
    _common_ready = _failures.is_empty()
    return _common_ready

func _resolve_skin_bone(skin: Skin, bind_idx: int) -> int:
    var bind_name := String(skin.get_bind_name(bind_idx))
    return _target.find_bone(bind_name) if not bind_name.is_empty() else skin.get_bind_bone(bind_idx)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child: Node in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _collect_skinned_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh != null and mesh_instance.skin != null:
            out.append(mesh_instance)
    for child: Node in node.get_children():
        _collect_skinned_meshes(child, out)

func _surface_key(mesh_instance: MeshInstance3D, surface_idx: int) -> String:
    return "%s#%d" % [String(mesh_instance.get_path()), surface_idx]

func _basis_delta_deg(a: Basis, b: Basis) -> float:
    var qa := a.orthonormalized().get_rotation_quaternion().normalized()
    var qb := b.orthonormalized().get_rotation_quaternion().normalized()
    var delta := (qa.inverse() * qb).normalized()
    return rad_to_deg(2.0 * atan2(Vector3(delta.x, delta.y, delta.z).length(), absf(delta.w)))

func _synthetic_rigid_edge_regression() -> bool:
    var points: Array[Vector3] = [Vector3.ZERO, Vector3(0.3, 0.1, -0.2), Vector3(-0.1, 0.4, 0.25)]
    var transform := Transform3D(Basis(Quaternion(Vector3(0.3, 0.7, 0.2).normalized(), deg_to_rad(37.0))), Vector3(2.0, -1.0, 0.5))
    var moved: Array[Vector3] = [transform * points[0], transform * points[1], transform * points[2]]
    for pair: Array in [[0, 1], [1, 2], [2, 0]]:
        var before: float = points[int(pair[0])].distance_to(points[int(pair[1])])
        var after: float = moved[int(pair[0])].distance_to(moved[int(pair[1])])
        if absf(before - after) > 0.00001:
            return false
    return true

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "\t"))
    file.close()

func _finish(result: Dictionary) -> void:
    result["failures"] = _failures
    _write_result(result)
    if not _failures.is_empty():
        for failure: String in _failures:
            push_error(failure)
        print("GATE8_VARIANT03_TARGET_MICROPOSE_BLOCKED state=%s failures=%d" % [String(result.get("diagnostic_state", "unknown")), _failures.size()])
        quit(1)
        return
    print("GATE8_VARIANT03_TARGET_MICROPOSE state=%s cases=%d blocked=%d edge=%.9f stretch=%.9f compression=%.9f" % [String(result.get("diagnostic_state", "unknown")), int(result.get("case_count", 0)), int(result.get("blocked_case_count", 0)), float(result.get("max_edge_absolute_change_m", 0.0)), float(result.get("max_edge_stretch_ratio", 1.0)), float(result.get("min_edge_compression_ratio", 1.0))])
    quit(0)
