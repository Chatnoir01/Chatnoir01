extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/npc_visual_quality_runtime.gd")


func _init() -> void:
	var failures: Array[String] = []
	var runtime := RUNTIME_SCRIPT.new()

	var civilian := Node3D.new()
	var head := _add_part(civilian, &"Head")
	head.position = Vector3(0.0, 0.87, 0.0)
	_add_part(civilian, &"Nose")
	_add_part(civilian, &"Neck")
	var left_hand := _add_part(civilian, &"LeftHand")
	left_hand.position = Vector3(-0.40, 0.0, 0.0)
	var right_hand := _add_part(civilian, &"RightHand")
	right_hand.position = Vector3(0.40, 0.0, 0.0)
	var left_shoe := _add_part(civilian, &"LeftShoe")
	left_shoe.position = Vector3(-0.11, -0.83, -0.07)
	var right_shoe := _add_part(civilian, &"RightShoe")
	right_shoe.position = Vector3(0.11, -0.83, -0.07)
	var left_arm := _add_part(civilian, &"LeftArm")
	left_arm.position = Vector3(-0.40, 0.30, 0.0)
	var right_arm := _add_part(civilian, &"RightArm")
	right_arm.position = Vector3(0.40, 0.30, 0.0)
	var left_leg := _add_part(civilian, &"LeftLeg")
	left_leg.position = Vector3(-0.11, -0.37, 0.0)
	var right_leg := _add_part(civilian, &"RightLeg")
	right_leg.position = Vector3(0.11, -0.37, 0.0)
	_add_part(civilian, &"Torso")
	_add_part(civilian, &"Hips")
	_add_part(civilian, &"OuterLayer")

	runtime.polish_visual(civilian, false)
	_assert_scale(failures, civilian, "Head", Vector3(0.36, 0.40, 0.38), "civilian head should use adult human proportions")
	_assert_scale(failures, civilian, "LeftHand", Vector3(0.50, 0.70, 0.50), "civilian hands should be compact")
	_assert_scale(failures, civilian, "LeftLeg", Vector3(0.62, 1.05, 0.64), "civilian legs should be slimmer without becoming shorter")
	_assert_scale(failures, civilian, "Torso", Vector3(0.68, 1.06, 0.76), "civilian torso should match the narrower adult silhouette")
	_assert_scale(failures, civilian, "OuterLayer", Vector3(0.74, 1.02, 0.80), "civilian outer layer should follow the corrected silhouette")
	_assert_position(failures, civilian, "Head", Vector3(0.0, 0.87, 0.0), "civilian head centre should preserve neck alignment")
	_assert_position(failures, civilian, "LeftArm", Vector3(-0.304, 0.30, 0.0), "civilian arms should sit on the narrowed shoulder line")
	_assert_position(failures, civilian, "RightArm", Vector3(0.304, 0.30, 0.0), "civilian arms should sit on the narrowed shoulder line")
	_assert_position(failures, civilian, "LeftShoe", Vector3(-0.1012, -0.842, -0.07), "civilian shoes should remain under the leg line")
	if civilian.get_node_or_null("PoliceQualityDetails") != null:
		failures.append("civilian must not receive police-only gear")
	if civilian.get_meta("npc_visual_quality_pass", "") != "v4":
		failures.append("civilian quality pass should be marked as v4")
	if civilian.get_meta("npc_visual_quality_silhouette", "") != "human-proportioned-v4":
		failures.append("civilian quality pass should publish the v4 silhouette contract")

	var head_scale_before := (civilian.get_node("Head") as Node3D).scale
	var arm_position_before := (civilian.get_node("LeftArm") as Node3D).position
	runtime.polish_visual(civilian, false)
	if (civilian.get_node("Head") as Node3D).scale.distance_to(head_scale_before) > 0.0001:
		failures.append("quality pass scale must be idempotent")
	if (civilian.get_node("LeftArm") as Node3D).position.distance_to(arm_position_before) > 0.0001:
		failures.append("quality pass position must be idempotent")

	var police := Node3D.new()
	_add_part(police, &"Head")
	_add_part(police, &"Hips").position = Vector3(0.0, -0.08, 0.0)
	var vest := _add_part(police, &"HiVisVest")
	vest.position = Vector3(0.0, 0.31, -0.005)
	_add_part(police, &"PoliceCap")
	_add_part(police, &"PoliceCapPeak")
	var label := Label3D.new()
	label.name = "UniformPoliceLabel"
	police.add_child(label)

	runtime.polish_visual(police, false)
	if label.visible:
		failures.append("floating police label should be hidden")
	_assert_scale(failures, police, "HiVisVest", Vector3(0.70, 0.96, 0.72), "police vest should follow the torso instead of reading as a block")
	_assert_scale(failures, police, "PoliceCap", Vector3(0.46, 0.62, 0.48), "police cap should fit the reduced head")
	if vest.material_override == null:
		failures.append("police vest should receive restrained navy material")
	var details := police.get_node_or_null("PoliceQualityDetails") as Node3D
	if details == null:
		failures.append("police should receive compact visual gear details")
	else:
		for detail_name: String in [
			"ReflectiveBandUpper",
			"ReflectiveBandLower",
			"ShoulderPatchLeft",
			"ShoulderPatchRight",
			"BodyCamera",
			"Radio",
			"DutyBelt",
			"BeltPouchLeft",
			"BeltPouchRight",
		]:
			if details.get_node_or_null(detail_name) == null:
				failures.append("police detail missing: %s" % detail_name)

	var ambient := Node3D.new()
	ambient.name = "AmbientPedestrian_00"
	_add_part(ambient, &"Torso").position = Vector3(0.0, 1.17, 0.0)
	var ambient_head := _add_part(ambient, &"Head")
	ambient_head.position = Vector3(0.0, 1.67, 0.0)
	var ambient_left_arm := _add_part(ambient, &"LeftArm")
	ambient_left_arm.position = Vector3(-0.33, 1.14, 0.0)
	var ambient_right_arm := _add_part(ambient, &"RightArm")
	ambient_right_arm.position = Vector3(0.33, 1.14, 0.0)
	var ambient_left_leg := _add_part(ambient, &"LeftLeg")
	ambient_left_leg.position = Vector3(-0.13, 0.48, 0.0)
	var ambient_right_leg := _add_part(ambient, &"RightLeg")
	ambient_right_leg.position = Vector3(0.13, 0.48, 0.0)
	_add_part(ambient, &"Bag")

	runtime.polish_ambient_pedestrian(ambient)
	_assert_scale(failures, ambient, "Head", Vector3(0.70, 0.70, 0.70), "Midi ambient head should be reduced")
	_assert_scale(failures, ambient, "Torso", Vector3(0.86, 1.10, 0.86), "Midi ambient torso should be taller and narrower")
	_assert_scale(failures, ambient, "LeftArm", Vector3(0.72, 1.08, 0.72), "Midi ambient arms should be slimmer")
	_assert_scale(failures, ambient, "LeftLeg", Vector3(0.86, 1.10, 0.82), "Midi ambient legs should be slightly taller and slimmer")
	_assert_position(failures, ambient, "Head", Vector3(0.0, 1.64, 0.0), "Midi ambient head should reconnect to the torso")
	_assert_position(failures, ambient, "LeftArm", Vector3(-0.297, 1.14, 0.0), "Midi ambient arm spacing should be narrower")
	_assert_position(failures, ambient, "LeftLeg", Vector3(-0.1222, 0.48, 0.0), "Midi ambient leg spacing should be natural")
	var ambient_details := ambient.get_node_or_null("AmbientQualityDetails") as Node3D
	if ambient_details == null:
		failures.append("Midi ambient pedestrian should receive close-camera details")
	else:
		for detail_name: String in ["HairCap", "LeftHand", "RightHand", "LeftShoe", "RightShoe"]:
			if ambient_details.get_node_or_null(detail_name) == null:
				failures.append("Midi ambient detail missing: %s" % detail_name)
	if ambient.get_meta("ambient_pedestrian_visual_quality", "") != "v1":
		failures.append("Midi ambient quality pass should be marked as v1")
	if ambient.get_meta("ambient_pedestrian_silhouette", "") != "midi-human-v1":
		failures.append("Midi ambient silhouette contract should be published")
	var ambient_head_before := (ambient.get_node("Head") as Node3D).scale
	runtime.polish_ambient_pedestrian(ambient)
	if (ambient.get_node("Head") as Node3D).scale.distance_to(ambient_head_before) > 0.0001:
		failures.append("Midi ambient quality pass must be idempotent")

	civilian.free()
	police.free()
	ambient.free()
	runtime.free()

	if failures.is_empty():
		print("NPC_VISUAL_QUALITY_RUNTIME_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("NPC_VISUAL_QUALITY_RUNTIME_FAIL: %s" % failure)
		quit(1)


func _add_part(parent: Node3D, part_name: StringName) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	parent.add_child(part)
	return part


func _assert_scale(failures: Array[String], root: Node3D, path: String, expected: Vector3, message: String) -> void:
	var part := root.get_node_or_null(path) as Node3D
	if part == null or part.scale.distance_to(expected) > 0.0001:
		failures.append(message)


func _assert_position(failures: Array[String], root: Node3D, path: String, expected: Vector3, message: String) -> void:
	var part := root.get_node_or_null(path) as Node3D
	if part == null or part.position.distance_to(expected) > 0.0001:
		failures.append(message)
