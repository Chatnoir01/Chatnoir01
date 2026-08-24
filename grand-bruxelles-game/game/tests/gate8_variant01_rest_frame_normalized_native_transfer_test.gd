extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const PROBE_DEGREES := 12.0
const MIN_SOURCE_DELTA_DEG := 11.5
const MAX_SOURCE_DELTA_DEG := 12.5
const MAX_TRANSFER_ERROR_DEG := 3.0
const MIN_TRANSFER_GAIN := 0.85
const MAX_TRANSFER_GAIN := 1.15
const MAX_RESET_RESIDUAL_DEG := 0.25
const MAX_REST_DRIFT_DEG := 0.001
const MAX_REST_ORIGIN_DRIFT_M := 0.000001
const MAX_SCALE_DRIFT := 0.0001

const ROLE_PAIRS := {
	"hips":["DEF-hips","pelvis"], "spine":["DEF-spine.001","spine_01"], "chest":["DEF-spine.002","spine_02"], "upper_chest":["DEF-spine.003","spine_03"], "neck":["DEF-neck","neck_01"], "head":["DEF-head","head"],
	"left_shoulder":["DEF-shoulder.L","clavicle_l"], "left_upper_arm":["DEF-upper_arm.L","upperarm_l"], "left_forearm":["DEF-forearm.L","lowerarm_l"], "left_hand":["DEF-hand.L","hand_l"],
	"right_shoulder":["DEF-shoulder.R","clavicle_r"], "right_upper_arm":["DEF-upper_arm.R","upperarm_r"], "right_forearm":["DEF-forearm.R","lowerarm_r"], "right_hand":["DEF-hand.R","hand_r"],
	"left_upper_leg":["DEF-thigh.L","thigh_l"], "left_lower_leg":["DEF-shin.L","calf_l"], "left_foot":["DEF-foot.L","foot_l"], "left_toe":["DEF-toe.L","ball_l"],
	"right_upper_leg":["DEF-thigh.R","thigh_r"], "right_lower_leg":["DEF-shin.R","calf_r"], "right_foot":["DEF-foot.R","foot_r"], "right_toe":["DEF-toe.R","ball_r"]
}
const EXPECTED_PARENT_ROLE := {
	"hips":"", "spine":"hips", "chest":"spine", "upper_chest":"chest", "neck":"upper_chest", "head":"neck",
	"left_shoulder":"upper_chest", "left_upper_arm":"left_shoulder", "left_forearm":"left_upper_arm", "left_hand":"left_forearm",
	"right_shoulder":"upper_chest", "right_upper_arm":"right_shoulder", "right_forearm":"right_upper_arm", "right_hand":"right_forearm",
	"left_upper_leg":"hips", "left_lower_leg":"left_upper_leg", "left_foot":"left_lower_leg", "left_toe":"left_foot",
	"right_upper_leg":"hips", "right_lower_leg":"right_upper_leg", "right_foot":"right_lower_leg", "right_toe":"right_foot"
}
const ROLE_ORDER := [
	"hips", "spine", "chest", "upper_chest", "neck", "head",
	"left_shoulder", "left_upper_arm", "left_forearm", "left_hand",
	"right_shoulder", "right_upper_arm", "right_forearm", "right_hand",
	"left_upper_leg", "left_lower_leg", "left_foot", "left_toe",
	"right_upper_leg", "right_lower_leg", "right_foot", "right_toe"
]

var failures:Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_scene := load(SOURCE_SCENE).instantiate() as Node3D
	var target_scene := load(TARGET_SCENE).instantiate() as Node3D
	if source_scene == null or target_scene == null:
		_finish({"failures":["scene_load_failed"]}); return
	root.add_child(source_scene); root.add_child(target_scene)
	await process_frame
	var source_real := _find_skeleton(source_scene)
	var target_real := _find_skeleton(target_scene)
	if source_real == null or target_real == null:
		_finish({"failures":["skeleton_missing"]}); return

	var source_roles := _resolve_roles(source_real, 0)
	var target_roles := _resolve_roles(target_real, 1)
	if source_roles.size() != ROLE_PAIRS.size() or target_roles.size() != ROLE_PAIRS.size():
		_finish({"failures":failures}); return
	_validate_topology(source_real, source_roles, "source")
	_validate_topology(target_real, target_roles, "target")
	if not failures.is_empty():
		_finish({"failures":failures}); return

	var source_rest_snapshot := _capture_rests(source_real, source_roles)
	var target_rest_snapshot := _capture_rests(target_real, target_roles)
	var source_probe := _build_target_rest_probe(target_real, target_roles, "NormalizedSource")
	var target_probe := _build_target_rest_probe(target_real, target_roles, "NormalizedTarget")
	root.add_child(source_probe)
	var modifier := RetargetModifier3D.new()
	modifier.name = "NativeRestNormalizedRetarget"
	source_probe.add_child(modifier)
	modifier.add_child(target_probe)
	var profile := _build_profile()
	modifier.set_use_global_pose(false)
	modifier.set_position_enabled(false)
	modifier.set_rotation_enabled(true)
	modifier.set_scale_enabled(false)
	modifier.set_profile(profile)
	await process_frame
	await process_frame

	var rows := {}
	var worst_error := 0.0
	var worst_role := ""
	var max_reset_residual := 0.0
	var max_scale_drift := 0.0
	var axis := Vector3(0.371, 0.733, 0.571).normalized()
	for role_value in ROLE_ORDER:
		var role := String(role_value)
		_reset_probe_to_rest(source_probe)
		_reset_probe_to_rest(target_probe)
		await process_frame
		await process_frame
		var source_index := source_probe.find_bone(_canonical(role))
		var target_index := target_probe.find_bone(_canonical(role))
		if source_index < 0 or target_index < 0:
			failures.append("probe_role_missing=%s" % role)
			continue
		var source_rest_q := _rest_rotation(source_probe, source_index)
		var target_rest_q := _rest_rotation(target_probe, target_index)
		var probe_delta := Quaternion(axis, deg_to_rad(PROBE_DEGREES)).normalized()
		# Godot 4 Skeleton3D poses are absolute. Normalize the authored rest-relative
		# delta into the target rest frame before the native modifier sees it:
		# D = Rs^-1 * Ps ; Pnormalized = Rt * D.
		var normalized_pose_q := (target_rest_q * probe_delta).normalized()
		source_probe.set_bone_pose_rotation(source_index, normalized_pose_q)
		await process_frame
		await process_frame
		var measured_source_q := source_probe.get_bone_pose_rotation(source_index).normalized()
		var measured_target_q := target_probe.get_bone_pose_rotation(target_index).normalized()
		var source_delta_deg := rad_to_deg(target_rest_q.angle_to(measured_source_q))
		var target_delta_deg := rad_to_deg(target_rest_q.angle_to(measured_target_q))
		var transfer_error_deg := absf(target_delta_deg - source_delta_deg)
		var transfer_gain := 0.0 if source_delta_deg <= 0.000001 else target_delta_deg / source_delta_deg
		if source_delta_deg < MIN_SOURCE_DELTA_DEG or source_delta_deg > MAX_SOURCE_DELTA_DEG:
			failures.append("source_delta_out_of_range=%s:%.6f" % [role, source_delta_deg])
		if transfer_error_deg > MAX_TRANSFER_ERROR_DEG:
			failures.append("transfer_error=%s:%.6f" % [role, transfer_error_deg])
		if transfer_gain < MIN_TRANSFER_GAIN or transfer_gain > MAX_TRANSFER_GAIN:
			failures.append("transfer_gain=%s:%.6f" % [role, transfer_gain])
		worst_error = maxf(worst_error, transfer_error_deg)
		if transfer_error_deg >= worst_error - 0.0000001:
			worst_role = role

		var target_rest_scale := target_probe.get_bone_rest(target_index).basis.get_scale()
		var target_pose_scale := target_probe.get_bone_pose_scale(target_index)
		var scale_drift := target_pose_scale.distance_to(target_rest_scale)
		max_scale_drift = maxf(max_scale_drift, scale_drift)
		if scale_drift > MAX_SCALE_DRIFT:
			failures.append("scale_drift=%s:%.9f" % [role, scale_drift])

		source_probe.set_bone_pose_rotation(source_index, source_rest_q)
		await process_frame
		await process_frame
		var reset_target_q := target_probe.get_bone_pose_rotation(target_index).normalized()
		var reset_residual_deg := rad_to_deg(target_rest_q.angle_to(reset_target_q))
		max_reset_residual = maxf(max_reset_residual, reset_residual_deg)
		if reset_residual_deg > MAX_RESET_RESIDUAL_DEG:
			failures.append("reset_residual=%s:%.6f" % [role, reset_residual_deg])
		rows[role] = {
			"source_delta_deg":source_delta_deg,
			"target_delta_deg":target_delta_deg,
			"transfer_error_deg":transfer_error_deg,
			"transfer_gain":transfer_gain,
			"reset_residual_deg":reset_residual_deg,
			"scale_drift":scale_drift,
		}

	_validate_rest_snapshot(source_real, source_roles, source_rest_snapshot, "source_real")
	_validate_rest_snapshot(target_real, target_roles, target_rest_snapshot, "target_real")
	if rows.size() != ROLE_PAIRS.size():
		failures.append("measured_roles=%d" % rows.size())
	var state := "READY_REST_NORMALIZED_ANIMATION_AB" if failures.is_empty() else "BLOCKED_REST_NORMALIZED_NATIVE_TRANSFER"
	var result := {
		"format":"grand-bruxelles-gate8-rest-frame-normalized-native-transfer-v1",
		"engine_version":Engine.get_version_info().get("string","unknown"),
		"candidate_variant":1,
		"reviewed_roles":ROLE_PAIRS.size(),
		"measured_roles":rows.size(),
		"probe_degrees":PROBE_DEGREES,
		"normalization_formula":"D=Rs^-1*Ps; Pnormalized=Rt*D",
		"native_modifier":"RetargetModifier3D",
		"use_global_pose":false,
		"position_enabled":false,
		"rotation_enabled":true,
		"scale_enabled":false,
		"roles":rows,
		"worst_role":worst_role,
		"max_transfer_error_deg":worst_error,
		"max_reset_residual_deg":max_reset_residual,
		"max_scale_drift":max_scale_drift,
		"source_target_assets_mutated":false,
		"rest_transforms_unchanged":not failures.any(func(v): return String(v).begins_with("rest_drift=")),
		"run_alias_selected":"",
		"production_authorized":false,
		"activation_ready":false,
		"adoption_ready":false,
		"selection_state":state,
		"failures":failures,
	}
	_finish(result)

func _resolve_roles(skeleton:Skeleton3D, name_slot:int) -> Dictionary:
	var result := {}
	for role_value in ROLE_ORDER:
		var role := String(role_value)
		var index := skeleton.find_bone(String(ROLE_PAIRS[role][name_slot]))
		if index < 0:
			failures.append("role_missing=%s:%s" % ["source" if name_slot == 0 else "target", role])
		else:
			result[role] = index
	return result

func _validate_topology(skeleton:Skeleton3D, roles:Dictionary, label:String) -> void:
	var role_by_bone := {}
	for role in roles:
		role_by_bone[int(roles[role])] = String(role)
	for role_value in ROLE_ORDER:
		var role := String(role_value)
		if not roles.has(role): continue
		var actual_parent := _nearest_mapped_parent_role(skeleton, int(roles[role]), role_by_bone)
		if actual_parent != String(EXPECTED_PARENT_ROLE[role]):
			failures.append("topology_mismatch=%s:%s:%s" % [label, role, actual_parent])

func _build_target_rest_probe(target_real:Skeleton3D, target_roles:Dictionary, node_name:String) -> Skeleton3D:
	var probe := Skeleton3D.new()
	probe.name = node_name
	var probe_index_by_role := {}
	for role_value in ROLE_ORDER:
		var role := String(role_value)
		var idx := probe.get_bone_count()
		probe.add_bone(_canonical(role))
		probe_index_by_role[role] = idx
		var parent_role := String(EXPECTED_PARENT_ROLE[role])
		if not parent_role.is_empty():
			probe.set_bone_parent(idx, int(probe_index_by_role[parent_role]))
		var target_rest := target_real.get_bone_rest(int(target_roles[role]))
		probe.set_bone_rest(idx, target_rest)
		probe.set_bone_pose_position(idx, target_rest.origin)
		probe.set_bone_pose_rotation(idx, target_rest.basis.orthonormalized().get_rotation_quaternion().normalized())
		probe.set_bone_pose_scale(idx, target_rest.basis.get_scale())
	return probe

func _build_profile() -> SkeletonProfile:
	var profile := SkeletonProfile.new()
	profile.set_bone_size(ROLE_ORDER.size())
	for i in range(ROLE_ORDER.size()):
		var role := String(ROLE_ORDER[i])
		profile.set_bone_name(i, _canonical(role))
		var parent_role := String(EXPECTED_PARENT_ROLE[role])
		profile.set_bone_parent(i, StringName() if parent_role.is_empty() else _canonical(parent_role))
		profile.set_required(i, true)
	profile.set_root_bone(_canonical("hips"))
	profile.set_scale_base_bone(_canonical("hips"))
	return profile

func _reset_probe_to_rest(skeleton:Skeleton3D) -> void:
	for i in range(skeleton.get_bone_count()):
		var rest := skeleton.get_bone_rest(i)
		skeleton.set_bone_pose_position(i, rest.origin)
		skeleton.set_bone_pose_rotation(i, rest.basis.orthonormalized().get_rotation_quaternion().normalized())
		skeleton.set_bone_pose_scale(i, rest.basis.get_scale())

func _capture_rests(skeleton:Skeleton3D, roles:Dictionary) -> Dictionary:
	var result := {}
	for role in roles:
		result[String(role)] = skeleton.get_bone_rest(int(roles[role]))
	return result

func _validate_rest_snapshot(skeleton:Skeleton3D, roles:Dictionary, snapshot:Dictionary, label:String) -> void:
	for role in roles:
		var before:Transform3D = snapshot[String(role)]
		var after := skeleton.get_bone_rest(int(roles[role]))
		var origin_drift := before.origin.distance_to(after.origin)
		var rotation_drift := rad_to_deg(before.basis.orthonormalized().get_rotation_quaternion().angle_to(after.basis.orthonormalized().get_rotation_quaternion()))
		if origin_drift > MAX_REST_ORIGIN_DRIFT_M or rotation_drift > MAX_REST_DRIFT_DEG:
			failures.append("rest_drift=%s:%s:%.9f:%.9f" % [label, String(role), origin_drift, rotation_drift])

func _nearest_mapped_parent_role(skeleton:Skeleton3D, index:int, role_by_bone:Dictionary) -> String:
	var parent := skeleton.get_bone_parent(index)
	while parent >= 0:
		if role_by_bone.has(parent): return String(role_by_bone[parent])
		parent = skeleton.get_bone_parent(parent)
	return ""

func _rest_rotation(skeleton:Skeleton3D, index:int) -> Quaternion:
	return skeleton.get_bone_rest(index).basis.orthonormalized().get_rotation_quaternion().normalized()

func _canonical(role:String) -> StringName:
	return StringName("gb_humanoid_%s" % role)

func _find_skeleton(node:Node) -> Skeleton3D:
	if node is Skeleton3D: return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null: return found
	return null

func _finish(result:Dictionary) -> void:
	var file := FileAccess.open("res://gate8_variant01_rest_frame_normalized_native_transfer.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "  ")); file.close()
	if result.has("failures") and (result.failures as Array).size() > 0:
		for failure in result.failures: push_error(String(failure))
		quit(1); return
	print("GATE8_REST_NORMALIZED_NATIVE_TRANSFER_OK roles=%d max_error_deg=%.6f max_reset_deg=%.6f production_authorized=false" % [int(result.measured_roles), float(result.max_transfer_error_deg), float(result.max_reset_residual_deg)])
	quit(0)
