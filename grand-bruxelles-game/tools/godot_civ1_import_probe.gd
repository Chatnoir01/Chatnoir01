extends SceneTree

const BODY_PATH := "res://vitruvian_body_sanitized.glb"

func fail(message: String) -> void:
	push_error("CIV1_GODOT_IMPORT_PROBE_FAIL " + message)
	quit(1)

func walk(node: Node, state: Dictionary) -> void:
	if node is Skeleton3D:
		state.skeleton_count += 1
		state.bone_count += node.get_bone_count()
	if node is MeshInstance3D:
		state.mesh_instance_count += 1
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.skin != null or not mesh_instance.skeleton.is_empty():
			state.skinned_mesh_count += 1
		var mesh := mesh_instance.mesh
		if mesh != null:
			state.mesh_resource_count += 1
			state.surface_count += mesh.get_surface_count()
			for surface_index in range(mesh.get_surface_count()):
				var material := mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh.surface_get_material(surface_index)
				if material != null:
					state.material_surface_count += 1
	for child in node.get_children():
		walk(child, state)

func _initialize() -> void:
	if not ResourceLoader.exists(BODY_PATH):
		fail("resource_missing path=" + BODY_PATH)
		return
	var packed := ResourceLoader.load(BODY_PATH)
	if packed == null or not packed is PackedScene:
		fail("resource_not_packed_scene path=" + BODY_PATH)
		return
	var root := (packed as PackedScene).instantiate()
	if root == null:
		fail("instantiate_failed")
		return
	var state := {
		"skeleton_count": 0,
		"bone_count": 0,
		"mesh_instance_count": 0,
		"mesh_resource_count": 0,
		"skinned_mesh_count": 0,
		"surface_count": 0,
		"material_surface_count": 0,
	}
	walk(root, state)
	if state.skeleton_count != 1:
		fail("skeleton_count=%d expected=1" % state.skeleton_count)
		return
	if state.bone_count <= 0:
		fail("bone_count=%d expected_positive" % state.bone_count)
		return
	if state.mesh_instance_count <= 0 or state.mesh_resource_count <= 0:
		fail("mesh_instances=%d mesh_resources=%d expected_positive" % [state.mesh_instance_count, state.mesh_resource_count])
		return
	if state.skinned_mesh_count <= 0:
		fail("skinned_mesh_count=0")
		return
	if state.surface_count <= 0:
		fail("surface_count=0")
		return
	if state.material_surface_count <= 0:
		fail("material_surface_count=0")
		return

	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		fail("expected_one_output_path")
		return
	var evidence := {
		"format": "grand-bruxelles-civ1-godot-import-evidence-v1",
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"source_resource": BODY_PATH,
		"skeleton_count": state.skeleton_count,
		"bone_count": state.bone_count,
		"mesh_instance_count": state.mesh_instance_count,
		"mesh_resource_count": state.mesh_resource_count,
		"skinned_mesh_count": state.skinned_mesh_count,
		"surface_count": state.surface_count,
		"material_surface_count": state.material_surface_count,
		"integrity": "validated",
	}
	var output_path := args[0]
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		fail("cannot_open_output path=" + output_path)
		return
	file.store_string(JSON.stringify(evidence, "  "))
	file.close()
	print("CIV1_GODOT_IMPORT_PROBE_OK skeletons=%d bones=%d meshes=%d skinned_meshes=%d surfaces=%d material_surfaces=%d" % [state.skeleton_count, state.bone_count, state.mesh_instance_count, state.skinned_mesh_count, state.surface_count, state.material_surface_count])
	root.free()
	quit(0)
