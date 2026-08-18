extends Node

const QUALITY_META := "npc_visual_quality_pass"
const QUALITY_VERSION := "v3"
const HUMANOID_VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")

const POLICE_NAVY := Color(0.025, 0.055, 0.12, 1.0)
const POLICE_DARK := Color(0.018, 0.026, 0.05, 1.0)
const POLICE_REFLECTIVE := Color(0.66, 0.71, 0.10, 1.0)


func _ready() -> void:
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	call_deferred("_polish_existing")


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _polish_existing() -> void:
	for agent_node: Node in get_tree().get_nodes_in_group("npc_agent"):
		_polish_agent(agent_node)


func _on_node_added(node: Node) -> void:
	if node == null:
		return
	if node.is_in_group("npc_agent"):
		call_deferred("_polish_agent", node)
		return
	if node is Node3D and _looks_like_humanoid_visual(node as Node3D):
		call_deferred("_polish_visual_candidate", node)


func _polish_agent(agent: Node) -> void:
	if not is_instance_valid(agent):
		return
	for child: Node in agent.get_children():
		if child is Node3D and _looks_like_humanoid_visual(child as Node3D):
			var police := agent.is_in_group("police_officer")
			polish_visual(child as Node3D, police)


func _polish_visual_candidate(visual: Node3D) -> void:
	if not is_instance_valid(visual):
		return
	var agent := visual.get_parent()
	if agent == null or not agent.is_in_group("npc_agent"):
		return
	polish_visual(visual, agent.is_in_group("police_officer"))


func _looks_like_humanoid_visual(node: Node3D) -> bool:
	return node.get_script() == HUMANOID_VISUAL_SCRIPT or node.name in [&"VisualUpgrade", &"HumanoidVisual"]


func polish_visual(visual: Node3D, police_hint: bool = false) -> void:
	if visual == null or visual.get_meta(QUALITY_META, "") == QUALITY_VERSION:
		return

	# The procedural generator uses generous half-extents that read as toy-like at
	# player distance. These factors target a roughly 7-7.5-head human silhouette
	# while retaining the lightweight mesh/variation system needed by Web builds.
	_scale_part(visual, &"Head", Vector3(0.36, 0.40, 0.38))
	_scale_part(visual, &"Nose", Vector3(0.42, 0.58, 0.42))
	_scale_part(visual, &"Neck", Vector3(0.58, 0.96, 0.60))
	_scale_part(visual, &"LeftHand", Vector3(0.50, 0.70, 0.50))
	_scale_part(visual, &"RightHand", Vector3(0.50, 0.70, 0.50))
	_scale_part(visual, &"LeftShoe", Vector3(0.72, 0.82, 0.72))
	_scale_part(visual, &"RightShoe", Vector3(0.72, 0.82, 0.72))
	_scale_part(visual, &"LeftArm", Vector3(0.52, 1.06, 0.54))
	_scale_part(visual, &"RightArm", Vector3(0.52, 1.06, 0.54))
	_scale_part(visual, &"LeftLeg", Vector3(0.62, 1.05, 0.64))
	_scale_part(visual, &"RightLeg", Vector3(0.62, 1.05, 0.64))
	_scale_part(visual, &"Torso", Vector3(0.68, 1.06, 0.76))
	_scale_part(visual, &"Hips", Vector3(0.76, 0.98, 0.78))
	_scale_part(visual, &"OuterLayer", Vector3(0.74, 1.02, 0.80))
	_scale_part(visual, &"HairCrown", Vector3(0.40, 0.42, 0.42))
	_scale_part(visual, &"HairVolume", Vector3(0.40, 0.42, 0.42))
	_scale_part(visual, &"HairBun", Vector3(0.55, 0.55, 0.55))
	_scale_part(visual, &"Beanie", Vector3(0.44, 0.50, 0.46))
	_scale_part(visual, &"CapCrown", Vector3(0.44, 0.50, 0.46))
	_scale_part(visual, &"CapPeak", Vector3(0.52, 0.64, 0.50))
	_scale_part(visual, &"RaisedHood", Vector3(0.52, 0.54, 0.54))

	# Bring limbs back onto the torso/hip lines after narrowing the geometry.
	_move_part_x_toward_center(visual, &"LeftArm", 0.76)
	_move_part_x_toward_center(visual, &"RightArm", 0.76)
	_move_part_x_toward_center(visual, &"LeftHand", 0.76)
	_move_part_x_toward_center(visual, &"RightHand", 0.76)
	_move_part_x_toward_center(visual, &"LeftLeg", 0.92)
	_move_part_x_toward_center(visual, &"RightLeg", 0.92)
	_move_part_x_toward_center(visual, &"LeftShoe", 0.92)
	_move_part_x_toward_center(visual, &"RightShoe", 0.92)
	_offset_part(visual, &"Beanie", Vector3(0.0, -0.075, 0.0))
	_offset_part(visual, &"CapCrown", Vector3(0.0, -0.075, 0.0))
	_offset_part(visual, &"CapPeak", Vector3(0.0, -0.075, 0.06))
	_offset_part(visual, &"LeftShoe", Vector3(0.0, -0.012, 0.0))
	_offset_part(visual, &"RightShoe", Vector3(0.0, -0.012, 0.0))

	var police := police_hint or visual.get_node_or_null("HiVisVest") != null or visual.get_node_or_null("UniformPoliceLabel") != null
	if police:
		_polish_police(visual)

	visual.set_meta(QUALITY_META, QUALITY_VERSION)
	visual.set_meta("npc_visual_quality_silhouette", "human-proportioned-v3")


func _scale_part(root: Node3D, child_name: StringName, multiplier: Vector3) -> void:
	var part := root.get_node_or_null(NodePath(str(child_name))) as Node3D
	if part == null:
		return
	part.scale = Vector3(
		part.scale.x * multiplier.x,
		part.scale.y * multiplier.y,
		part.scale.z * multiplier.z
	)


func _offset_part(root: Node3D, child_name: StringName, offset: Vector3) -> void:
	var part := root.get_node_or_null(NodePath(str(child_name))) as Node3D
	if part == null:
		return
	part.position += offset


func _move_part_x_toward_center(root: Node3D, child_name: StringName, factor: float) -> void:
	var part := root.get_node_or_null(NodePath(str(child_name))) as Node3D
	if part == null:
		return
	part.position.x *= factor


func _polish_police(visual: Node3D) -> void:
	var label := visual.get_node_or_null("UniformPoliceLabel") as Label3D
	if label != null:
		label.visible = false

	var vest := visual.get_node_or_null("HiVisVest") as MeshInstance3D
	if vest != null:
		vest.scale = Vector3(vest.scale.x * 0.70, vest.scale.y * 0.96, vest.scale.z * 0.72)
		vest.material_override = _material(POLICE_NAVY, 0.88)

	_scale_part(visual, &"PoliceCap", Vector3(0.46, 0.62, 0.48))
	_scale_part(visual, &"PoliceCapPeak", Vector3(0.55, 0.70, 0.50))
	_offset_part(visual, &"PoliceCap", Vector3(0.0, -0.10, 0.0))
	_offset_part(visual, &"PoliceCapPeak", Vector3(0.0, -0.10, 0.10))

	if visual.get_node_or_null("PoliceQualityDetails") != null:
		return

	var details := Node3D.new()
	details.name = "PoliceQualityDetails"
	visual.add_child(details)

	var reflective := _material(POLICE_REFLECTIVE, 0.72)
	var dark := _material(POLICE_DARK, 0.92)
	var navy := _material(POLICE_NAVY.lightened(0.08), 0.90)
	var chest_y := 0.31
	var chest_z := -0.14
	if vest != null:
		chest_y = vest.position.y
		chest_z = vest.position.z - 0.13

	_add_box(details, &"ReflectiveBandUpper", Vector3(0.36, 0.024, 0.018), Vector3(0.0, chest_y + 0.065, chest_z), reflective)
	_add_box(details, &"ReflectiveBandLower", Vector3(0.34, 0.022, 0.018), Vector3(0.0, chest_y - 0.070, chest_z), reflective)
	_add_box(details, &"ShoulderPatchLeft", Vector3(0.065, 0.030, 0.045), Vector3(-0.16, chest_y + 0.21, -0.06), navy)
	_add_box(details, &"ShoulderPatchRight", Vector3(0.065, 0.030, 0.045), Vector3(0.16, chest_y + 0.21, -0.06), navy)
	_add_box(details, &"BodyCamera", Vector3(0.052, 0.072, 0.026), Vector3(0.060, chest_y + 0.090, chest_z - 0.02), dark)
	_add_box(details, &"Radio", Vector3(0.048, 0.095, 0.030), Vector3(-0.12, chest_y + 0.075, chest_z - 0.015), dark)

	var hips := visual.get_node_or_null("Hips") as Node3D
	var belt_y := -0.08
	if hips != null:
		belt_y = hips.position.y + 0.040
	_add_box(details, &"DutyBelt", Vector3(0.33, 0.038, 0.14), Vector3(0.0, belt_y, -0.005), dark)
	_add_box(details, &"BeltPouchLeft", Vector3(0.058, 0.075, 0.045), Vector3(-0.125, belt_y - 0.038, -0.080), dark)
	_add_box(details, &"BeltPouchRight", Vector3(0.058, 0.075, 0.045), Vector3(0.125, belt_y - 0.038, -0.080), dark)


func _add_box(parent: Node3D, part_name: StringName, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_instance)
	return mesh_instance


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
