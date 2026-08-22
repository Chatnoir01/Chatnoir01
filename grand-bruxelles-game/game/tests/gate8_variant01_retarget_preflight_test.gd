extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const RESULT_PATH := "res://gate8_variant01_retarget_preflight_result.json"
const LOCOMOTION_TOKENS := ["idle", "walk", "run"]
const REJECT_TOKENS := {
	"attack": true,
	"combat": true,
	"fire": true,
	"shoot": true,
	"punch": true,
	"kick": true,
	"sword": true,
	"gun": true,
	"to": true,
	"transition": true,
	"start": true,
	"stop": true,
	"turn": true,
	"strafe": true,
	"back": true,
	"backward": true,
	"reverse": true,
}
const ANCHOR_SUFFIXES := {
	"hips": ["hips", "pelvis"],
	"spine": ["spine", "spine1", "spine01", "spine001"],
	"chest": ["upperchest", "chest", "spine2", "spine02", "spine002", "spine3", "spine03", "spine003"],
	"head": ["head"],
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


func _tokens_for_name(value: String) -> Array[String]:
	var normalized := value.to_lower()
	for separator in ["_", "-", ".", "/", ":", "(", ")", "[", "]", "{​", "}"]:
		normalized = normalized.replace(separator, " ")
	var tokens: Array[String] = []
	for raw_token in normalized.split(" ", false):
		var token := String(raw_token).strip_edges()
		if not token.is_empty():
			tokens.append(token)
	return tokens


func _classify_locomotion(value: String) -> Array[String]:
	var tokens := _tokens_for_name(value)
	for token in tokens:
		if REJECT_TOKENS.has(token):
			return []
	var hits: Array[String] = []
	for locomotion_token in LOCOMOTION_TOKENS:
		if tokens.has(locomotion_token):
			hits.append(locomotion_token)
	return hits


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


func _collect_meshes(node: Node, output: Array) -> void:
	if node is MeshInstance3D:
		output.append(node)
	for child in node.get_children():
		_collect_meshes(child, output)


func _unique_sorted_strings(values: Array[String]) -> Array[String]:
	var seen := {}
	for value in values:
		seen[value] = true
	var result: Array[String] = []
	for value in seen.keys():
		result.append(String(value))
	result.sort()
	return result


func _animation_names(players: Array) -> Array[String]:
	var names: Array[String] = []
	for player in players:
		for animation_name in player.get_animation_list():
			var value := String(animation_name)
			if value.to_lower() == "reset":
				continue
			names.append(value)
	return _unique_sorted_strings(names)


func _bone_names(skeletons: Array) -> Array[String]:
	var names: Array[String] = []
	for skeleton in skeletons:
		for bone_index in range(skeleton.get_bone_count()):
			names.append(String(skeleton.get_bone_name(bone_index)))
	return _unique_sorted_strings(names)


func _anchor_inventory(bone_names: Array[String]) -> Dictionary:
	var inventory := {}
	for anchor_name in ANCHOR_SUFFIXES.keys():
		var matches: Array[String] = []
		for bone_name in bone_names:
			var compact := _compact_name(bone_name)
			for suffix in ANCHOR_SUFFIXES[anchor_name]:
				if compact.ends_with(String(suffix)):
					matches.append(bone_name)
					break
		inventory[anchor_name] = _unique_sorted_strings(matches)
	return inventory


func _count_skinned_meshes(meshes: Array) -> int:
	var count := 0
	for mesh_instance in meshes:
		if mesh_instance.skin != null or not mesh_instance.skeleton.is_empty():
			count += 1
	return count


func _write_result(result: Dictionary) -> void:
	var output := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if output == null:
		_fail("result_file_open_failed")
		return
	output.store_string(JSON.stringify(result, "\t") + "\n")
	output.close()


func _run_classifier_regressions() -> void:
	_require(_classify_locomotion("Attack_Run") == [], "classifier_attack_run_not_rejected")
	_require(_classify_locomotion("Idle_To_Walk") == [], "classifier_idle_to_walk_not_rejected")
	_require(_classify_locomotion("Walk_To_Idle") == [], "classifier_walk_to_idle_not_rejected")
	_require(_classify_locomotion("Walk_Backward") == [], "classifier_walk_backward_not_rejected")
	_require(_classify_locomotion("Run_Start") == [], "classifier_run_start_not_rejected")
	_require(_classify_locomotion("Runway_Look") == [], "classifier_runway_false_positive")
	_require(_classify_locomotion("Backpack_Walk") == ["walk"], "classifier_backpack_walk_false_negative")
	_require(_classify_locomotion("Civil_Idle") == ["idle"], "classifier_idle_false_negative")
	_require(_classify_locomotion("Civil_Run") == ["run"], "classifier_run_false_negative")


func _run() -> void:
	_run_classifier_regressions()

	var source_resource := load(SOURCE_SCENE)
	var target_resource := load(TARGET_SCENE)
	_require(source_resource is PackedScene, "source_glb_not_imported_as_packed_scene")
	_require(target_resource is PackedScene, "target_glb_not_imported_as_packed_scene")
	if not (source_resource is PackedScene) or not (target_resource is PackedScene):
		_write_result({"format": "grand-bruxelles-gate8-variant01-retarget-preflight-result-v1", "failures": _failures})
		quit(1)
		return

	var source_root: Node = source_resource.instantiate()
	var target_root: Node = target_resource.instantiate()
	get_root().add_child(source_root)
	get_root().add_child(target_root)

	var source_skeletons: Array = []
	var target_skeletons: Array = []
	var source_players: Array = []
	var target_players: Array = []
	var source_meshes: Array = []
	var target_meshes: Array = []
	_collect_skeletons(source_root, source_skeletons)
	_collect_skeletons(target_root, target_skeletons)
	_collect_animation_players(source_root, source_players)
	_collect_animation_players(target_root, target_players)
	_collect_meshes(source_root, source_meshes)
	_collect_meshes(target_root, target_meshes)

	var source_names := _animation_names(source_players)
	var target_names := _animation_names(target_players)
	var candidates := {"idle": [], "walk": [], "run": []}
	for animation_name in source_names:
		for token in _classify_locomotion(animation_name):
			candidates[token].append(animation_name)
	for token in LOCOMOTION_TOKENS:
		candidates[token] = _unique_sorted_strings(candidates[token])

	var complete_locomotion_surface := true
	var exact_single_trio := true
	for token in LOCOMOTION_TOKENS:
		complete_locomotion_surface = complete_locomotion_surface and candidates[token].size() > 0
		exact_single_trio = exact_single_trio and candidates[token].size() == 1

	var source_bones := _bone_names(source_skeletons)
	var target_bones := _bone_names(target_skeletons)
	var source_anchors := _anchor_inventory(source_bones)
	var target_anchors := _anchor_inventory(target_bones)
	var source_skinned_meshes := _count_skinned_meshes(source_meshes)
	var target_skinned_meshes := _count_skinned_meshes(target_meshes)

	_require(source_skeletons.size() >= 1, "source_skeleton_missing")
	_require(target_skeletons.size() >= 1, "target_skeleton_missing")
	_require(source_players.size() >= 1, "source_animation_player_missing")
	_require(source_names.size() > 0, "source_animation_catalog_empty")
	_require(target_players.size() == 0, "target_should_remain_animation_free_before_retarget")
	_require(target_names.size() == 0, "target_animation_catalog_should_be_empty_before_retarget")
	_require(target_skinned_meshes >= 1, "target_skinned_mesh_missing")
	_require(complete_locomotion_surface, "source_exact_token_idle_walk_run_surface_incomplete")
	_require(source_anchors["hips"].size() > 0, "source_hips_anchor_missing")
	_require(target_anchors["hips"].size() > 0, "target_hips_anchor_missing")
	_require(source_anchors["head"].size() > 0, "source_head_anchor_missing")
	_require(target_anchors["head"].size() > 0, "target_head_anchor_missing")
	_require(source_anchors["left_foot"].size() > 0, "source_left_foot_anchor_missing")
	_require(source_anchors["right_foot"].size() > 0, "source_right_foot_anchor_missing")
	_require(target_anchors["left_foot"].size() > 0, "target_left_foot_anchor_missing")
	_require(target_anchors["right_foot"].size() > 0, "target_right_foot_anchor_missing")

	var result := {
		"format": "grand-bruxelles-gate8-variant01-retarget-preflight-result-v1",
		"engine_version": String(Engine.get_version_info().get("string", "unknown")),
		"candidate_variant": 1,
		"candidate_static_verdict": "AMELIORER",
		"source_animation_players": source_players.size(),
		"source_animation_count": source_names.size(),
		"source_animation_names": source_names,
		"target_animation_players": target_players.size(),
		"target_animation_count": target_names.size(),
		"locomotion_candidates": candidates,
		"complete_exact_token_locomotion_surface": complete_locomotion_surface,
		"exact_single_idle_walk_run_trio": exact_single_trio,
		"source_skeletons": source_skeletons.size(),
		"target_skeletons": target_skeletons.size(),
		"source_skinned_meshes": source_skinned_meshes,
		"target_skinned_meshes": target_skinned_meshes,
		"source_bones": source_bones,
		"target_bones": target_bones,
		"source_humanoid_anchors": source_anchors,
		"target_humanoid_anchors": target_anchors,
		"source_upper_chest_candidates": source_anchors["chest"].size(),
		"target_upper_chest_candidates": target_anchors["chest"].size(),
		"retarget_applied": false,
		"production_authorized": false,
		"activation_ready": false,
		"adoption_ready": false,
		"grounding_measured": false,
		"foot_slide_measured": false,
		"player_view_reviewed": false,
		"failures": _failures,
	}
	_write_result(result)

	print(
		"GATE8_VARIANT01_RETARGET_PREFLIGHT " +
		"candidate=01 " +
		"source_animations=%d target_animations=%d " % [source_names.size(), target_names.size()] +
		"idle_candidates=%d walk_candidates=%d run_candidates=%d " % [candidates["idle"].size(), candidates["walk"].size(), candidates["run"].size()] +
		"exact_single_trio=%s " % str(exact_single_trio).to_lower() +
		"source_skeletons=%d target_skeletons=%d " % [source_skeletons.size(), target_skeletons.size()] +
		"source_upper_chest=%d target_upper_chest=%d " % [source_anchors["chest"].size(), target_anchors["chest"].size()] +
		"target_skinned_meshes=%d retarget_applied=false production_authorized=false" % target_skinned_meshes
	)
	print("GATE8_VARIANT01_IDLE_CANDIDATES " + str(candidates["idle"]))
	print("GATE8_VARIANT01_WALK_CANDIDATES " + str(candidates["walk"]))
	print("GATE8_VARIANT01_RUN_CANDIDATES " + str(candidates["run"]))

	source_root.queue_free()
	target_root.queue_free()
	if _failures.is_empty():
		print("GATE8_VARIANT01_RETARGET_PREFLIGHT_OK")
		quit(0)
	else:
		print("GATE8_VARIANT01_RETARGET_PREFLIGHT_FAIL failures=" + str(_failures))
		quit(1)
