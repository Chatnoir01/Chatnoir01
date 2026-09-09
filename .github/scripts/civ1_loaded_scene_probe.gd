extends SceneTree

const SCHEMA := "grand-bruxelles-civ1-loaded-scene-probe-v1"
const CANONICAL_SCENE := "res://game/main.tscn"
const DEFAULT_OUTPUT := "/tmp/civ1-loaded-scene-probe.json"

var _scene_root: Node = null

func _initialize() -> void:
	call_deferred("_run_probe")

func _transform_dict(value: Transform3D) -> Dictionary:
	return {
		"origin_m": [value.origin.x, value.origin.y, value.origin.z],
		"basis_rows": [
			[value.basis.x.x, value.basis.y.x, value.basis.z.x],
			[value.basis.x.y, value.basis.y.y, value.basis.z.y],
			[value.basis.x.z, value.basis.y.z, value.basis.z.z],
		],
	}

func _relative_path(node: Node) -> String:
	if _scene_root == null:
		return ""
	return str(_scene_root.get_path_to(node))

func _find_skeleton(root_node: Node) -> Skeleton3D:
	if root_node is Skeleton3D:
		return root_node as Skeleton3D
	for child in root_node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _collect_character_bodies(root_node: Node, out: Array) -> void:
	if root_node is CharacterBody3D:
		out.append(root_node)
	for child in root_node.get_children():
		_collect_character_bodies(child, out)

func _write_result(result: Dictionary, exit_code: int) -> void:
	var output_path := OS.get_environment("CIV1_LOADED_SCENE_PROBE_OUT")
	if output_path.is_empty():
		output_path = DEFAULT_OUTPUT
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("CIV1_LOADED_SCENE_PROBE_WRITE_FAIL ", output_path)
		quit(3)
		return
	file.store_string(JSON.stringify(result, "  "))
	file.store_string("\n")
	file.close()
	print("CIV1_LOADED_SCENE_PROBE ", JSON.stringify(result))
	quit(exit_code)

func _run_probe() -> void:
	var result := {
		"schema": SCHEMA,
		"engine_version": Engine.get_version_info().get("string", "unknown"),
		"canonical_scene": CANONICAL_SCENE,
		"canonical_scene_loaded": false,
		"ground_found": false,
		"ground": {},
		"character_body_count": 0,
		"npc_candidates": [],
		"exact_npc_hierarchy_found": false,
		"capture_available": false,
		"capture_reason": "canonical_scene_not_loaded",
		"animation_samples_captured": false,
		"canonical_export_modified": false,
		"probe_scope": "ephemeral-qa-only",
	}
	var packed := load(CANONICAL_SCENE) as PackedScene
	if packed == null:
		_write_result(result, 2)
		return
	_scene_root = packed.instantiate()
	if _scene_root == null:
		result["capture_reason"] = "canonical_scene_not_instantiated"
		_write_result(result, 2)
		return
	get_root().add_child(_scene_root)
	await process_frame
	await process_frame
	result["canonical_scene_loaded"] = true

	var ground := _scene_root.get_node_or_null("Ground")
	if ground != null:
		result["ground_found"] = true
		var ground_entry := {
			"path": "Main/Ground",
			"loaded_relative_path": _relative_path(ground),
			"class": ground.get_class(),
		}
		if ground is Node3D:
			ground_entry["world_transform"] = _transform_dict((ground as Node3D).global_transform)
		result["ground"] = ground_entry

	var bodies: Array = []
	_collect_character_bodies(_scene_root, bodies)
	result["character_body_count"] = bodies.size()
	var candidates: Array = []
	for body_variant in bodies:
		var body := body_variant as CharacterBody3D
		if body == null:
			continue
		var entry := {
			"path": _relative_path(body),
			"name": str(body.name),
			"class": body.get_class(),
			"world_transform": _transform_dict(body.global_transform),
			"character_mount_found": false,
			"skeleton_found": false,
		}
		var mount := body.find_child("CharacterMount", true, false)
		if mount != null and mount is Node3D:
			entry["character_mount_found"] = true
			entry["character_mount"] = {
				"path": _relative_path(mount),
				"class": mount.get_class(),
				"world_transform": _transform_dict((mount as Node3D).global_transform),
			}
			var skeleton := _find_skeleton(mount)
			if skeleton != null:
				entry["skeleton_found"] = true
				entry["skeleton"] = {
					"path": _relative_path(skeleton),
					"class": skeleton.get_class(),
					"world_transform": _transform_dict(skeleton.global_transform),
				}
				result["exact_npc_hierarchy_found"] = true
		candidates.append(entry)
	result["npc_candidates"] = candidates
	if bool(result["exact_npc_hierarchy_found"]) and bool(result["ground_found"]):
		result["capture_available"] = true
		result["capture_reason"] = "loaded_hierarchy_observed_samples_not_captured"
	else:
		result["capture_reason"] = "canonical_scene_has_no_civ1_hierarchy"

	# This probe intentionally never fabricates animation frames 71/72/73.
	# A full runtime-placement witness remains fail-closed until those samples
	# are captured from the actual loaded Skeleton/animation state.
	_write_result(result, 0)
