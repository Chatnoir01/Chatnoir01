extends Node

const QUALITY_META := "npc_visual_quality_pass"
const QUALITY_VERSION := "v1"
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

	# The procedural NPC mesh is kept as a lightweight Web-safe fallback, but its
	# toy-like proportions are corrected at runtime: smaller head/hands/feet,
	# slimmer limbs and a slightly taller, narrower silhouette.
	_scale_part(visual, &"Head", Vector3(0.86, 0.90, 0.88))
	_scale_part(visual, &"Nose", Vector3(0.52, 0.70, 0.50))
	_scale_part(visual, &"LeftHand", Vector3(0.78, 0.82, 0.78))
	_scale_part(visual, &"RightHand", Vector3(0.78, 0.82, 0.78))
	_scale_part(visual, &"LeftShoe", Vector3(0.84, 0.90, 0.82))
	_scale_part(visual, &"RightShoe", Vector3(0.84, 0.90, 0.82))
	_scale_part(visual, &"LeftArm", Vector3(0.88, 1.00, 0.88))
	_scale_part(visual, &"RightArm", Vector3(0.88, 1.00, 0.88))
	_scale_part(visual, &"LeftLeg", Vector3(0.90, 1.02, 0.90))
	_scale_part(visual, &"RightLeg", Vector3(0.90, 1.02, 0.90))
	_scale_part(visual, &"Torso", Vector3(0.93, 1.03, 0.90))
	_scale_part(visual, &"Hips", Vector3(0.93, 0.96, 0.92))
	_scale_part(visual, &"HairCrown", Vector3(0.94, 0.92, 0.94))
	_scale_part(visual, &"HairVolume", Vector3(0.94, 0.92, 0.94))
	_scale_part(visual, &"HairBun", Vector3(0.90, 0.90, 0.90))

	var police := police_hint or visual.get_node_or_null("HiVisVest") != null or visual.get_node_or_null("UniformPoliceLabel") != null
	if police:
		_polish_police(visual)

	visual.set_meta(QUALITY_META, QUALITY_VERSION)


func _scale_part(root: Node3D, child_name: StringName, multiplier: Vector3) -> void:
	var part := root.get_node_or_null(NodePath(str(child_name))) as Node3D
	if part == null:
		return
	part.scale = Vector3(
		part.scale.x * multiplier.x,
		part.scale.y * multiplier.y,
		part.scale.z * multiplier.z
	)


func _polish_police(visual: Node3D) -> void:
	var label := visual.get_node_or_null("UniformPoliceLabel") as Label3D
	if label != null:
		label.visible = false

	var vest := visual.get_node_or_null("HiVisVest") as MeshInstance3D
	if vest != null:
		vest.scale = Vector3(vest.scale.x * 0.93, vest.scale.y * 0.94, vest.scale.z * 0.88)
		vest.material_override = _material(POLICE_NAVY, 0.88)

	_scale_part(visual, &"PoliceCap", Vector3(0.91, 0.90, 0.91))
	_scale_part(visual, &"PoliceCapPeak", Vector3(0.80, 0.82, 0.78))

	if visual.get_node_or_null("PoliceQualityDetails") != null:
		return

	var details := Node3D.new()
	details.name = "PoliceQualityDetails"
	visual.add_child(details)

	var reflective := _material(POLICE_REFLECTIVE, 0.72)
	var dark := _material(POLICE_DARK, 0.92)
	var chest_y := 0.31
	var chest_z := -0.20
	if vest != null:
		chest_y = vest.position.y
		chest_z = vest.position.z - 0.19

	_add_box(details, &"ReflectiveBandUpper", Vector3(0.50, 0.035, 0.025), Vector3(0.0, chest_y + 0.075, chest_z), reflective)
	_add_box(details, &"ReflectiveBandLower", Vector3(0.46, 0.030, 0.025), Vector3(0.0, chest_y - 0.085, chest_z), reflective)
	_add_box(details, &"BodyCamera", Vector3(0.075, 0.10, 0.035), Vector3(0.09, chest_y + 0.10, chest_z - 0.02), dark)
	_add_box(details, &"Radio", Vector3(0.065, 0.13, 0.04), Vector3(-0.18, chest_y + 0.08, chest_z - 0.015), dark)

	var hips := visual.get_node_or_null("Hips") as Node3D
	var belt_y := -0.08
	if hips != null:
		belt_y = hips.position.y + 0.07
	_add_box(details, &"DutyBelt", Vector3(0.43, 0.055, 0.20), Vector3(0.0, belt_y, -0.01), dark)


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
