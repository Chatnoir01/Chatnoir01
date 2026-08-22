extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const RESULT_PATH := "res://gate8_variant01_run_semantic_ab_result.json"
const CLIPS := ["Jog_Fwd", "Sprint"]
const SAMPLE_RATE_HZ := 120.0
const ANCHOR_SUFFIXES := {
	"hips": ["hips", "pelvis"],
	"left_foot": ["leftfoot", "lfoot", "footl"],
	"right_foot": ["rightfoot", "rfoot", "footr"],
}

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)

func _require(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

func _compact_name(value: String) -> String:
	var normalized := value.to_lower()
	for separator in ["_", "-", ".", " ", ":", "/", "\\", "(", ")", "[", "]"]:
		normalized = normalized.replace(separator, "")
	return normalized

func _collect_skeletons(node: Node, output: Array) -> void:
	if node is Skeleton3D:
		output.append(node)
	for child in node.get_children():
		_collect_skeletons(child, output)

func _collect_animation_players(node: Node, output: Array) -> void:
	if node is AnimationPlayer:
		output.append(node)
	for child in node.get_children():
		_collect_animation_players(child, output)

func _find_bone_index(skeleton: Skeleton3D, anchor_name: String) -> int:
	for bone_index in range(skeleton.get_bone_count()):
		var compact := _compact_name(String(skeleton.get_bone_name(bone_index)))
		for suffix in ANCHOR_SUFFIXES[anchor_name]:
			if compact.ends_with(String(suffix)):
				return bone_index
	return -1

func _find_player_with_clips(players: Array) -> AnimationPlayer:
	for player in players:
		var valid := true
		for clip_name in CLIPS:
			valid = valid and player.has_animation(clip_name)
		if valid:
			return player
	return null

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _contact_metrics(samples: Array, threshold_y: float, dt: float) -> Dictionary:
	var strike_count := 0
	var contact_intervals := 0
	var slide_sum_m := 0.0
	var slide_max_mps := 0.0
	var previous_contact := false
	for index in range(samples.size()):
		var current: Vector3 = samples[index]
		var current_contact := current.y <= threshold_y
		if current_contact and not previous_contact:
			strike_count += 1
		if index > 0:
			var previous: Vector3 = samples[index - 1]
			var previous_is_contact := previous.y <= threshold_y
			if current_contact and previous_is_contact:
				var slide_m: float = _horizontal_distance(previous, current)
				var slide_mps: float = slide_m / dt if dt > 0.0 else 0.0
				slide_sum_m += slide_m
				contact_intervals += 1
				slide_max_mps = maxf(slide_max_mps, slide_mps)
		previous_contact = current_contact
	var mean_slide_mps := 0.0
	if contact_intervals > 0 and dt > 0.0:
		mean_slide_mps = slide_sum_m / (float(contact_intervals) * dt)
	return {
		"strike_count": strike_count,
		"contact_intervals": contact_intervals,
		"contact_slide_total_m": slide_sum_m,
		"contact_slide_mean_mps": mean_slide_mps,
		"contact_slide_max_mps": slide_max_mps,
	}

func _measure_clip(player: AnimationPlayer, skeleton: Skeleton3D, clip_name: String, hips_index: int, left_foot_index: int, right_foot_index: int) -> Dictionary:
	var animation: Animation = player.get_animation(clip_name)
	_require(animation != null, "missing_animation_%s" % clip_name)
	if animation == null:
		return {}
	var length: float = float(animation.length)
	_require(length > 0.2 and length <= 10.0, "clip_length_out_of_range_%s" % clip_name)
	var sample_count: int = maxi(3, int(ceil(length * SAMPLE_RATE_HZ)) + 1)
	var dt: float = length / float(sample_count - 1)
	var hips_samples: Array = []
	var left_samples: Array = []
	var right_samples: Array = []

	player.play(clip_name)
	for index in range(sample_count):
		var time: float = minf(length, float(index) * dt)
		player.seek(time, true)
		player.advance(0.0)
		hips_samples.append(skeleton.get_bone_global_pose(hips_index).origin)
		left_samples.append(skeleton.get_bone_global_pose(left_foot_index).origin)
		right_samples.append(skeleton.get_bone_global_pose(right_foot_index).origin)
	player.stop()

	var hips_start: Vector3 = hips_samples.front()
	var hips_end: Vector3 = hips_samples.back()
	var hips_displacement_m: float = _horizontal_distance(hips_start, hips_end)
	var hips_path_m := 0.0
	for index in range(1, hips_samples.size()):
		hips_path_m += _horizontal_distance(hips_samples[index - 1], hips_samples[index])

	var left_min_y := INF
	var left_max_y := -INF
	var right_min_y := INF
	var right_max_y := -INF
	for value in left_samples:
		var point: Vector3 = value
		left_min_y = minf(left_min_y, point.y)
		left_max_y = maxf(left_max_y, point.y)
	for value in right_samples:
		var point: Vector3 = value
		right_min_y = minf(right_min_y, point.y)
		right_max_y = maxf(right_max_y, point.y)
	var left_threshold: float = left_min_y + maxf(0.015, (left_max_y - left_min_y) * 0.20)
	var right_threshold: float = right_min_y + maxf(0.015, (right_max_y - right_min_y) * 0.20)
	var left_contact: Dictionary = _contact_metrics(left_samples, left_threshold, dt)
	var right_contact: Dictionary = _contact_metrics(right_samples, right_threshold, dt)
	var total_strikes: int = int(left_contact["strike_count"]) + int(right_contact["strike_count"])
	var steps_per_minute: float = (float(total_strikes) / length) * 60.0 if length > 0.0 else 0.0
	var mean_contact_slide_mps: float = (float(left_contact["contact_slide_mean_mps"]) + float(right_contact["contact_slide_mean_mps"])) * 0.5
	var max_contact_slide_mps: float = maxf(float(left_contact["contact_slide_max_mps"]), float(right_contact["contact_slide_max_mps"]))
	var root_motion_mode := "traveling" if hips_displacement_m >= 0.15 else "in_place"

	for metric in [length, hips_displacement_m, hips_path_m, steps_per_minute, mean_contact_slide_mps, max_contact_slide_mps]:
		_require(_finite(float(metric)), "non_finite_metric_%s" % clip_name)
	_require(total_strikes >= 1, "no_foot_strikes_detected_%s" % clip_name)
	_require(int(left_contact["contact_intervals"]) + int(right_contact["contact_intervals"]) >= 1, "no_foot_contact_intervals_%s" % clip_name)

	return {
		"clip": clip_name,
		"length_s": length,
		"sample_rate_hz": SAMPLE_RATE_HZ,
		"sample_count": sample_count,
		"hips_horizontal_displacement_m": hips_displacement_m,
		"hips_horizontal_path_m": hips_path_m,
		"root_motion_mode": root_motion_mode,
		"left_foot_min_y": left_min_y,
		"left_foot_max_y": left_max_y,
		"right_foot_min_y": right_min_y,
		"right_foot_max_y": right_max_y,
		"left_contact_threshold_y": left_threshold,
		"right_contact_threshold_y": right_threshold,
		"left_contact": left_contact,
		"right_contact": right_contact,
		"total_foot_strikes": total_strikes,
		"steps_per_minute": steps_per_minute,
		"contact_slide_mean_mps": mean_contact_slide_mps,
		"contact_slide_max_mps": max_contact_slide_mps,
	}

func _write_result(result: Dictionary) -> void:
	var output := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if output == null:
		_fail("result_file_open_failed")
		return
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()

func _run_regressions() -> void:
	_require(absf(_horizontal_distance(Vector3(0, 0, 0), Vector3(0, 5, 0))) <= 0.000001, "horizontal_distance_vertical_leak")
	_require(absf(_horizontal_distance(Vector3(0, 0, 0), Vector3(3, 4, 4)) - 5.0) <= 0.000001, "horizontal_distance_xz_regression")
	var stationary := [Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0)]
	var moving := [Vector3(0, 0, 0), Vector3(0.1, 0, 0), Vector3(0.2, 0, 0)]
	var stationary_metrics := _contact_metrics(stationary, 0.01, 0.1)
	var moving_metrics := _contact_metrics(moving, 0.01, 0.1)
	_require(absf(float(stationary_metrics["contact_slide_mean_mps"])) <= 0.000001, "stationary_contact_slide_nonzero")
	_require(float(moving_metrics["contact_slide_mean_mps"]) > 0.5, "moving_contact_slide_not_detected")

func _run() -> void:
	_run_regressions()
	var source_resource := load(SOURCE_SCENE)
	_require(source_resource is PackedScene, "source_glb_not_imported_as_packed_scene")
	if not (source_resource is PackedScene):
		_write_result({"format": "grand-bruxelles-gate8-variant01-run-semantic-ab-result-v1", "failures": _failures})
		quit(1)
		return

	var source_root: Node = source_resource.instantiate()
	get_root().add_child(source_root)
	var skeletons: Array = []
	var players: Array = []
	_collect_skeletons(source_root, skeletons)
	_collect_animation_players(source_root, players)
	_require(skeletons.size() == 1, "expected_exactly_one_source_skeleton")
	var player := _find_player_with_clips(players)
	_require(player != null, "animation_player_with_both_candidates_missing")
	if skeletons.size() != 1 or player == null:
		_write_result({"format": "grand-bruxelles-gate8-variant01-run-semantic-ab-result-v1", "failures": _failures})
		quit(1)
		return

	var skeleton: Skeleton3D = skeletons[0]
	var hips_index := _find_bone_index(skeleton, "hips")
	var left_foot_index := _find_bone_index(skeleton, "left_foot")
	var right_foot_index := _find_bone_index(skeleton, "right_foot")
	_require(hips_index >= 0, "hips_anchor_missing")
	_require(left_foot_index >= 0, "left_foot_anchor_missing")
	_require(right_foot_index >= 0, "right_foot_anchor_missing")
	if hips_index < 0 or left_foot_index < 0 or right_foot_index < 0:
		_write_result({"format": "grand-bruxelles-gate8-variant01-run-semantic-ab-result-v1", "failures": _failures})
		quit(1)
		return

	var measurements := {}
	for clip_name in CLIPS:
		measurements[clip_name] = _measure_clip(player, skeleton, clip_name, hips_index, left_foot_index, right_foot_index)

	var result := {
		"format": "grand-bruxelles-gate8-variant01-run-semantic-ab-result-v1",
		"engine_version": String(Engine.get_version_info().get("string", "unknown")),
		"candidate_variant": 1,
		"candidate_static_verdict": "AMELIORER",
		"source_dynamic_state": "BLOCKED_NO_EXACT_RUN",
		"clips": CLIPS,
		"measurements": measurements,
		"cadence_measured": true,
		"hips_horizontal_motion_measured": true,
		"foot_contact_slide_measured": true,
		"run_alias_selected": "",
		"selection_state": "MEASURED_REVIEW_REQUIRED",
		"semantic_alias_auto_promotion_allowed": false,
		"bone_map_applied": false,
		"retarget_applied": false,
		"production_authorized": false,
		"activation_ready": false,
		"adoption_ready": false,
		"failures": _failures,
	}
	_write_result(result)
	for clip_name in CLIPS:
		var metric: Dictionary = measurements[clip_name]
		print("GATE8_VARIANT01_RUN_AB clip=%s length_s=%.4f steps_per_minute=%.2f hips_displacement_m=%.4f hips_path_m=%.4f root_motion=%s contact_slide_mean_mps=%.4f contact_slide_max_mps=%.4f" % [clip_name, float(metric["length_s"]), float(metric["steps_per_minute"]), float(metric["hips_horizontal_displacement_m"]), float(metric["hips_horizontal_path_m"]), String(metric["root_motion_mode"]), float(metric["contact_slide_mean_mps"]), float(metric["contact_slide_max_mps"])])
	if _failures.is_empty():
		print("GATE8_VARIANT01_RUN_SEMANTIC_AB_OK state=MEASURED_REVIEW_REQUIRED alias_selected=false retarget_applied=false production_authorized=false")
		quit(0)
	else:
		print("GATE8_VARIANT01_RUN_SEMANTIC_AB_FAIL count=%d" % _failures.size())
		quit(1)
