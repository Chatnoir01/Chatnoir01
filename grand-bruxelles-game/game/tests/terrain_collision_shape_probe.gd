extends SceneTree

const PROBE_FORMAT := "grand-bruxelles-terrain-collision-godot-probe-v1"
const RESULT_FORMAT := "grand-bruxelles-terrain-collision-godot-result-v1"
const EXPECTED_ENGINE_VERSION := "4.7.1"

var _failure_count := 0
var _probe_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _user_arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


func _engine_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d" % [int(info.get("major", 0)), int(info.get("minor", 0)), int(info.get("patch", 0))]


func _write_result(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("TERRAIN_COLLISION_GODOT_FAIL cannot_write_result path=%s" % path)
		return false
	file.store_string(JSON.stringify(payload, "\t", true) + "\n")
	file.close()
	return true


func _run() -> void:
	var probe_root := _user_arg_value("--probe-root=")
	var result_root := _user_arg_value("--result-root=")
	if probe_root.is_empty() or result_root.is_empty():
		push_error("TERRAIN_COLLISION_GODOT_FAIL missing_probe_or_result_root")
		quit(1)
		return

	if DirAccess.make_dir_recursive_absolute(result_root) != OK:
		push_error("TERRAIN_COLLISION_GODOT_FAIL cannot_create_result_root=%s" % result_root)
		quit(1)
		return

	var directory := DirAccess.open(probe_root)
	if directory == null:
		push_error("TERRAIN_COLLISION_GODOT_FAIL cannot_open_probe_root=%s" % probe_root)
		quit(1)
		return

	var files := directory.get_files()
	files.sort()
	for filename in files:
		if not filename.ends_with(".json"):
			continue
		_probe_count += 1
		var ok := await _probe_file(probe_root.path_join(filename), result_root.path_join(filename))
		if not ok:
			_failure_count += 1

	if _probe_count == 0:
		push_error("TERRAIN_COLLISION_GODOT_FAIL no_probe_files")
		quit(1)
		return

	if _failure_count > 0:
		print("TERRAIN_COLLISION_GODOT_COMPLETE probes=%d failed=%d" % [_probe_count, _failure_count])
		quit(1)
		return

	print("TERRAIN_COLLISION_GODOT_OK probes=%d failed=0 multiraycast=true engine=%s" % [_probe_count, _engine_version()])
	quit(0)


func _probe_file(probe_path: String, result_path: String) -> bool:
	var text := FileAccess.get_file_as_string(probe_path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TERRAIN_COLLISION_GODOT_FAIL invalid_json path=%s" % probe_path)
		return false
	var probe: Dictionary = parsed
	var cell_id := str(probe.get("cell_id", ""))
	var probe_digest := str(probe.get("probe_digest", ""))
	var engine_version := _engine_version()

	var base_result := {
		"format": RESULT_FORMAT,
		"cell_id": cell_id,
		"probe_digest": probe_digest,
		"engine_version": engine_version,
		"passed": false,
		"status": "failed_probe_contract",
		"metrics": {},
	}

	if probe.get("format") != PROBE_FORMAT or probe.get("crs") != "EPSG:31370":
		_write_result(result_path, base_result)
		return false
	if engine_version != EXPECTED_ENGINE_VERSION:
		base_result["status"] = "failed_engine_version"
		_write_result(result_path, base_result)
		return false

	var width := int(probe.get("map_width", 0))
	var depth := int(probe.get("map_depth", 0))
	var spacing := float(probe.get("spacing_m", 0.0))
	var raw_data = probe.get("map_data", [])
	if typeof(raw_data) != TYPE_ARRAY or width < 2 or depth < 2 or spacing <= 0.0 or raw_data.size() != width * depth:
		base_result["status"] = "failed_heightmap_dimensions"
		_write_result(result_path, base_result)
		return false

	var raw_samples = probe.get("raycast_samples", [])
	if typeof(raw_samples) != TYPE_ARRAY or raw_samples.size() < 4:
		base_result["status"] = "failed_raycast_samples_contract"
		_write_result(result_path, base_result)
		return false

	# HeightMapShape3D grid points are one unit apart. Use a uniform node scale so
	# this probe is valid with both Jolt and GodotPhysics3D. Heights are divided by
	# spacing before upload, so the uniform Y scale reconstructs the exact world Y.
	var map_data := PackedFloat32Array()
	map_data.resize(raw_data.size())
	for index in range(raw_data.size()):
		var height := float(raw_data[index])
		if not is_finite(height):
			base_result["status"] = "failed_nonfinite_height"
			_write_result(result_path, base_result)
			return false
		map_data[index] = height / spacing

	var shape := HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = depth
	shape.map_data = map_data

	var body := StaticBody3D.new()
	body.name = "TerrainCollisionProbe_%s" % cell_id
	body.collision_layer = 1
	body.collision_mask = 1
	var collision := CollisionShape3D.new()
	collision.name = "HeightMapCollision"
	collision.shape = shape
	collision.scale = Vector3(spacing, spacing, spacing)
	body.add_child(collision)
	get_root().add_child(body)
	await physics_frame

	var raycast_results: Array = []
	var all_samples_passed := true
	var max_raycast_error := 0.0
	for raw_sample in raw_samples:
		if typeof(raw_sample) != TYPE_DICTIONARY:
			all_samples_passed = false
			continue
		var sample: Dictionary = raw_sample
		var sample_id := int(sample.get("sample_id", -1))
		var sample_row := int(sample.get("row", -1))
		var sample_column := int(sample.get("column", -1))
		var local_x := float(sample.get("local_x_m", 0.0))
		var local_z := float(sample.get("local_z_m", 0.0))
		var expected_height := float(sample.get("expected_height_m", 0.0))
		var tolerance := float(sample.get("maximum_abs_error_m", 0.0))
		if sample_id < 0 or sample_row < 0 or sample_column < 0 or tolerance <= 0.0:
			all_samples_passed = false
			raycast_results.append({
				"sample_id": sample_id,
				"row": sample_row,
				"column": sample_column,
				"expected_height_m": expected_height,
				"hit": false,
				"hit_height_m": null,
				"abs_error_m": null,
				"maximum_abs_error_m": tolerance,
			})
			continue

		var ray_from := Vector3(local_x, expected_height + 1000.0, local_z)
		var ray_to := Vector3(local_x, expected_height - 1000.0, local_z)
		var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		var raycast_hit := not hit.is_empty()
		var hit_height := 0.0
		var raycast_error := INF
		if raycast_hit:
			var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
			hit_height = hit_position.y
			raycast_error = abs(hit_height - expected_height)
			if is_finite(raycast_error):
				max_raycast_error = maxf(max_raycast_error, raycast_error)
		var sample_passed := raycast_hit and is_finite(raycast_error) and raycast_error <= tolerance
		all_samples_passed = all_samples_passed and sample_passed
		raycast_results.append({
			"sample_id": sample_id,
			"row": sample_row,
			"column": sample_column,
			"expected_height_m": expected_height,
			"hit": raycast_hit,
			"hit_height_m": hit_height if raycast_hit else null,
			"abs_error_m": raycast_error if is_finite(raycast_error) else null,
			"maximum_abs_error_m": tolerance,
		})

	var shape_created := shape.map_width == width and shape.map_depth == depth and shape.map_data.size() == width * depth
	var shape_rid_valid := shape.get_rid().is_valid()
	var body_inside_tree := body.is_inside_tree()
	var min_height_world := shape.get_min_height() * spacing
	var max_height_world := shape.get_max_height() * spacing
	var passed: bool = (
		shape_created
		and shape_rid_valid
		and body_inside_tree
		and raycast_results.size() == raw_samples.size()
		and all_samples_passed
	)

	var result := {
		"format": RESULT_FORMAT,
		"cell_id": cell_id,
		"probe_digest": probe_digest,
		"engine_version": engine_version,
		"passed": passed,
		"status": "passed_heightmap_shape_staticbody_multiraycast" if passed else "failed_heightmap_shape_staticbody_multiraycast",
		"metrics": {
			"map_width": shape.map_width,
			"map_depth": shape.map_depth,
			"map_data_count": shape.map_data.size(),
			"shape_created": shape_created,
			"shape_rid_valid": shape_rid_valid,
			"body_inside_tree": body_inside_tree,
			"shape_min_height_m": min_height_world,
			"shape_max_height_m": max_height_world,
			"raycast_samples": raycast_results,
			"raycast_sample_count": raycast_results.size(),
			"raycast_max_abs_error_m": max_raycast_error if all_samples_passed else null,
			"collision_scale_xyz_m": spacing,
			"height_data_prescale_inverse_spacing": true,
		},
	}
	var wrote := _write_result(result_path, result)
	body.queue_free()
	await process_frame

	if passed and wrote:
		print(
			"TERRAIN_COLLISION_GODOT_CELL_OK cell=%s shape=%dx%d samples=%d max_ray_error_m=%.6f collision_authorized=false"
			% [cell_id, width, depth, raycast_results.size(), max_raycast_error]
		)
		return true
	push_error("TERRAIN_COLLISION_GODOT_CELL_FAIL cell=%s status=%s samples=%d" % [cell_id, result["status"], raycast_results.size()])
	return false
