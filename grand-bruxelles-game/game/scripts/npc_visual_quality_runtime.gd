extends Node

const QUALITY_META := "npc_visual_quality_pass"
const QUALITY_VERSION := "v4"
const AMBIENT_QUALITY_META := "ambient_pedestrian_visual_quality"
const AMBIENT_QUALITY_VERSION := "v1"
const HUMANOID_VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")

const POLICE_NAVY := Color(0.025, 0.055, 0.12, 1.0)
const POLICE_DARK := Color(0.018, 0.026, 0.05, 1.0)
const POLICE_REFLECTIVE := Color(0.66, 0.71, 0.10, 1.0)
const AMBIENT_SKIN_FALLBACK := Color(0.62, 0.43, 0.31, 1.0)


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
	for pedestrian_node: Node in get_tree().get_nodes_in_group("ambient_pedestrian"):
		if pedestrian_node is Node3D:
			polish_ambient_pedestrian(pedestrian_node as Node3D)


func _on_node_added(node: Node) -> void:
	if node == null:
		return
	if node.is_in_group("ambient_pedestrian") and node is Node3D:
		# MidiUrbanLife adds the person node before its body parts. Deferred polish
		# therefore observes the complete lightweight pedestrian on the next idle turn.
		call_deferred("polish_ambient_pedestrian", node)
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
	visual.set_meta("npc_visual_quality_silhouette", "human-proportioned-v4")


func polish_ambient_pedestrian(person: Node3D) -> void:
	if person == null or person.get_meta(AMBIENT_QUALITY_META, "") == AMBIENT_QUALITY_VERSION:
		return
	if person.get_node_or_null("Torso") == null or person.get_node_or_null("Head") == null:
		return

	# Midi's 20 ambient pedestrians are a second, older population layer and are
	# not NpcAgent instances. Correct them too, otherwise the largest close-camera
	# civilians still keep the old box + oversized-sphere prototype silhouette.
	_scale_part(person, &"Head", Vector3(0.70, 0.70, 0.70))
	_offset_part(person, &"Head", Vector3(0.0, -0.030, 0.0))
	_scale_part(person, &"Torso", Vector3(0.86, 1.10, 0.86))
	_scale_part(person, &"LeftArm", Vector3(0.72, 1.08, 0.72))
	_scale_part(person, &"RightArm", Vector3(0.72, 1.08, 0.72))
	_scale_part(person, &"LeftLeg", Vector3(0.86, 1.10, 0.82))
	_scale_part(person, &"RightLeg", Vector3(0.86, 1.10, 0.82))
	_scale_part(person, &"Bag", Vector3(0.82, 0.92, 0.82))
	_move_part_x_toward_center(person, &"LeftArm", 0.90)
	_move_part_x_toward_center(person, &"RightArm", 0.90)
	_move_part_x_toward_center(person, &"LeftLeg", 0.94)
	_move_part_x_toward_center(person, &"RightLeg", 0.94)

	if person.get_node_or_null("AmbientQualityDetails") == null:
		var details := Node3D.new()
		details.name = "AmbientQualityDetails"
		person.add_child(details)

		var skin_material := _mesh_material(person.get_node_or_null("Head") as MeshInstance3D)
		if skin_material == null:
			skin_material = _material(AMBIENT_SKIN_FALLBACK, 0.80)
		var shoe_material := _material(Color(0.045, 0.05, 0.06, 1.0), 0.90)
		var hair_variant := posmod(str(person.name).hash(), 3)
		var hair_color := Color(0.035, 0.027, 0.022, 1.0)
		if hair_variant == 1:
			hair_color = Color(0.10, 0.058, 0.035, 1.0)
		elif hair_variant == 2:
			hair_color = Color(0.20, 0.13, 0.075, 1.0)
		var hair_material := _material(hair_color, 0.92)

		var head := person.get_node_or_null("Head") as Node3D
		var head_position := Vector3(0.0, 1.64, 0.0)
		if head != null:
			head_position = head.position
		var hair := _add_sphere(details, &"HairCap", 0.158, head_position + Vector3(0.0, 0.105, 0.012), hair_material)
		hair.scale = Vector3(1.02, 0.42, 1.02)

		var left_arm := person.get_node_or_null("LeftArm") as Node3D
		var right_arm := person.get_node_or_null("RightArm") as Node3D
		var left_hand_x := -0.297
		var right_hand_x := 0.297
		if left_arm != null:
			left_hand_x = left_arm.position.x
		if right_arm != null:
			right_hand_x = right_arm.position.x
		_add_sphere(details, &"LeftHand", 0.052, Vector3(left_hand_x, 0.785, 0.0), skin_material)
		_add_sphere(details, &"RightHand", 0.052, Vector3(right_hand_x, 0.785, 0.0), skin_material)

		var left_leg := person.get_node_or_null("LeftLeg") as Node3D
		var right_leg := person.get_node_or_null("RightLeg") as Node3D
		var left_shoe_x := -0.122
		var right_shoe_x := 0.122
		if left_leg != null:
			left_shoe_x = left_leg.position.x
		if right_leg != null:
			right_shoe_x = right_leg.position.x
		_add_box(details, &"LeftShoe", Vector3(0.145, 0.095, 0.245), Vector3(left_shoe_x, 0.095, -0.045), shoe_material)
		_add_box(details, &"RightShoe", Vector3(0.145, 0.095, 0.245), Vector3(right_shoe_x, 0.095, -0.045), shoe_material)

	person.set_meta(AMBIENT_QUALITY_META, AMBIENT_QUALITY_VERSION)
	person.set_meta("ambient_pedestrian_silhouette", "midi-human-v1")


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


func _mesh_material(mesh_instance: MeshInstance3D) -> Material:
	if mesh_instance == null:
		return null
	if mesh_instance.material_override != null:
		return mesh_instance.material_override
	if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
		return mesh_instance.mesh.surface_get_material(0)
	return null


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


func _add_sphere(parent: Node3D, part_name: StringName, radius: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	mesh_instance.mesh = sphere
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
