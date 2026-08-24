extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
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
const BILATERAL_PAIRS := [
	["left_shoulder","right_shoulder"], ["left_upper_arm","right_upper_arm"], ["left_forearm","right_forearm"], ["left_hand","right_hand"],
	["left_upper_leg","right_upper_leg"], ["left_lower_leg","right_lower_leg"], ["left_foot","right_foot"], ["left_toe","right_toe"]
]
const MAX_BILATERAL_LOCAL_DELTA_DIFF_DEG := 1.0
const MAX_BILATERAL_DIRECTION_DELTA_DIFF_DEG := 1.0
const MAX_BILATERAL_LENGTH_RATIO_DIFF := 0.02

var failures:Array[String]=[]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_scene := load(SOURCE_SCENE).instantiate() as Node3D
	var target_scene := load(TARGET_SCENE).instantiate() as Node3D
	if source_scene == null or target_scene == null:
		_finish({"failures":["scene_load_failed"]}); return
	root.add_child(source_scene); root.add_child(target_scene)
	await process_frame
	var source := _find_skeleton(source_scene)
	var target := _find_skeleton(target_scene)
	if source == null or target == null:
		_finish({"failures":["skeleton_missing"]}); return

	var source_role_by_bone := {}
	var target_role_by_bone := {}
	for role in ROLE_PAIRS:
		var source_name := String(ROLE_PAIRS[role][0])
		var target_name := String(ROLE_PAIRS[role][1])
		var source_index := source.find_bone(source_name)
		var target_index := target.find_bone(target_name)
		if source_index < 0 or target_index < 0:
			failures.append("role_missing=%s" % role)
			continue
		source_role_by_bone[source_index] = String(role)
		target_role_by_bone[target_index] = String(role)

	var rows := {}
	var topology_mismatches:Array[String] = []
	for role in ROLE_PAIRS:
		var source_index := source.find_bone(String(ROLE_PAIRS[role][0]))
		var target_index := target.find_bone(String(ROLE_PAIRS[role][1]))
		if source_index < 0 or target_index < 0:
			continue
		var source_rest := source.get_bone_rest(source_index)
		var target_rest := target.get_bone_rest(target_index)
		var source_q := source_rest.basis.orthonormalized().get_rotation_quaternion().normalized()
		var target_q := target_rest.basis.orthonormalized().get_rotation_quaternion().normalized()
		var correction := (target_q * source_q.inverse()).normalized()
		var corrected_source_q := (correction * source_q).normalized()
		var reconstruction_error_deg := rad_to_deg(corrected_source_q.angle_to(target_q))
		var local_delta_deg := rad_to_deg(source_q.angle_to(target_q))

		var source_parent_role := _nearest_mapped_parent_role(source, source_index, source_role_by_bone)
		var target_parent_role := _nearest_mapped_parent_role(target, target_index, target_role_by_bone)
		var expected_parent := String(EXPECTED_PARENT_ROLE[role])
		if source_parent_role != expected_parent or target_parent_role != expected_parent:
			topology_mismatches.append(String(role))

		var direction_delta_deg := 0.0
		var segment_length_ratio := 1.0
		var source_parent := source.get_bone_parent(source_index)
		var target_parent := target.get_bone_parent(target_index)
		if source_parent >= 0 and target_parent >= 0:
			var source_dir := source.get_bone_global_rest(source_index).origin - source.get_bone_global_rest(source_parent).origin
			var target_dir := target.get_bone_global_rest(target_index).origin - target.get_bone_global_rest(target_parent).origin
			if source_dir.length() <= 0.000001 or target_dir.length() <= 0.000001:
				failures.append("zero_segment=%s" % role)
			else:
				direction_delta_deg = rad_to_deg(source_dir.normalized().angle_to(target_dir.normalized()))
				segment_length_ratio = target_dir.length() / source_dir.length()

		rows[role] = {
			"source_bone": source.get_bone_name(source_index),
			"target_bone": target.get_bone_name(target_index),
			"source_parent_role": source_parent_role,
			"target_parent_role": target_parent_role,
			"expected_parent_role": expected_parent,
			"local_rest_delta_deg": local_delta_deg,
			"parent_child_direction_delta_deg": direction_delta_deg,
			"segment_length_ratio": segment_length_ratio,
			"normalization_correction_quaternion": [correction.x, correction.y, correction.z, correction.w],
			"normalization_reconstruction_error_deg": reconstruction_error_deg,
		}

	var bilateral_rows := {}
	var bilateral_asymmetries:Array[String] = []
	for pair in BILATERAL_PAIRS:
		var left_role := String(pair[0]); var right_role := String(pair[1])
		if not rows.has(left_role) or not rows.has(right_role):
			failures.append("bilateral_role_missing=%s/%s" % [left_role,right_role]); continue
		var left:Dictionary = rows[left_role]; var right:Dictionary = rows[right_role]
		var local_diff := absf(float(left.local_rest_delta_deg) - float(right.local_rest_delta_deg))
		var direction_diff := absf(float(left.parent_child_direction_delta_deg) - float(right.parent_child_direction_delta_deg))
		var length_diff := absf(float(left.segment_length_ratio) - float(right.segment_length_ratio))
		var symmetric := local_diff <= MAX_BILATERAL_LOCAL_DELTA_DIFF_DEG and direction_diff <= MAX_BILATERAL_DIRECTION_DELTA_DIFF_DEG and length_diff <= MAX_BILATERAL_LENGTH_RATIO_DIFF
		if not symmetric:
			bilateral_asymmetries.append("%s/%s" % [left_role,right_role])
		bilateral_rows["%s/%s" % [left_role,right_role]] = {
			"local_delta_difference_deg": local_diff,
			"direction_delta_difference_deg": direction_diff,
			"length_ratio_difference": length_diff,
			"symmetric": symmetric,
		}

	var max_reconstruction_error := 0.0
	for role in rows:
		max_reconstruction_error = maxf(max_reconstruction_error, float((rows[role] as Dictionary).normalization_reconstruction_error_deg))
	if max_reconstruction_error > 0.001:
		failures.append("normalization_reconstruction_error_deg=%.9f" % max_reconstruction_error)
	if topology_mismatches.size() > 0:
		failures.append("topology_mismatches=%s" % ",".join(topology_mismatches))
	if bilateral_asymmetries.size() > 0:
		failures.append("bilateral_asymmetries=%s" % ",".join(bilateral_asymmetries))

	var selection_state := "REST_FRAME_NORMALIZATION_PREFERRED"
	if not failures.is_empty():
		selection_state = "ROLE_MAPPING_REVIEW_REQUIRED"
	var result := {
		"format":"grand-bruxelles-gate8-rest-frame-normalization-plan-v1",
		"engine_version":Engine.get_version_info().get("string","unknown"),
		"candidate_variant":1,
		"reviewed_roles":ROLE_PAIRS.size(),
		"measured_roles":rows.size(),
		"topology_mismatch_roles":topology_mismatches,
		"bilateral_asymmetry_pairs":bilateral_asymmetries,
		"bilateral_pairs":bilateral_rows,
		"roles":rows,
		"max_normalization_reconstruction_error_deg":max_reconstruction_error,
		"normalization_mutation_applied":false,
		"retarget_applied":false,
		"run_alias_selected":"",
		"production_authorized":false,
		"activation_ready":false,
		"adoption_ready":false,
		"selection_state":selection_state,
		"failures":failures,
	}
	_finish(result)

func _nearest_mapped_parent_role(skeleton:Skeleton3D, index:int, role_by_bone:Dictionary) -> String:
	var parent := skeleton.get_bone_parent(index)
	while parent >= 0:
		if role_by_bone.has(parent):
			return String(role_by_bone[parent])
		parent = skeleton.get_bone_parent(parent)
	return ""

func _find_skeleton(node:Node)->Skeleton3D:
	if node is Skeleton3D: return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null: return found
	return null

func _finish(result:Dictionary)->void:
	var file := FileAccess.open("res://gate8_variant01_rest_frame_normalization_plan.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result,"  ")); file.close()
	if result.has("failures") and (result.failures as Array).size() > 0:
		for failure in result.failures: push_error(String(failure))
		quit(1); return
	print("GATE8_REST_FRAME_NORMALIZATION_PLAN_OK roles=%d topology=0 bilateral_asymmetry=0 production_authorized=false" % int(result.get("measured_roles",0)))
	quit(0)
