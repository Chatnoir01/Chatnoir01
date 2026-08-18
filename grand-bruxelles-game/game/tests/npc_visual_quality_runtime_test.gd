extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/npc_visual_quality_runtime.gd")


func _init() -> void:
	var failures: Array[String] = []
	var runtime := RUNTIME_SCRIPT.new()

	var civilian := Node3D.new()
	_add_part(civilian, &"Head")
	_add_part(civilian, &"Nose")
	_add_part(civilian, &"LeftHand")
	_add_part(civilian, &"RightHand")
	_add_part(civilian, &"LeftShoe")
	_add_part(civilian, &"RightShoe")
	_add_part(civilian, &"LeftArm")
	_add_part(civilian, &"RightArm")
	_add_part(civilian, &"LeftLeg")
	_add_part(civilian, &"RightLeg")
	_add_part(civilian, &"Torso")
	_add_part(civilian, &"Hips")

	runtime.polish_visual(civilian, false)
	_assert_scale(failures, civilian, "Head", Vector3(0.86, 0.90, 0.88), "civilian head should be reduced")
	_assert_scale(failures, civilian, "LeftHand", Vector3(0.78, 0.82, 0.78), "civilian hands should be reduced")
	_assert_scale(failures, civilian, "Torso", Vector3(0.93, 1.03, 0.90), "civilian torso should be narrower and slightly taller")
	if civilian.get_node_or_null("PoliceQualityDetails") != null:
		failures.append("civilian must not receive police-only gear")
	if civilian.get_meta("npc_visual_quality_pass", "") != "v1":
		failures.append("civilian quality pass should be marked as applied")

	var head_before := (civilian.get_node("Head") as Node3D).scale
	runtime.polish_visual(civilian, false)
	if (civilian.get_node("Head") as Node3D).scale.distance_to(head_before) > 0.0001:
		failures.append("quality pass must be idempotent")

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
	if vest.material_override == null:
		failures.append("oversized hi-vis vest should receive restrained police material")
	var details := police.get_node_or_null("PoliceQualityDetails") as Node3D
	if details == null:
		failures.append("police should receive compact visual gear details")
	else:
		for detail_name: String in ["ReflectiveBandUpper", "ReflectiveBandLower", "BodyCamera", "Radio", "DutyBelt"]:
			if details.get_node_or_null(detail_name) == null:
				failures.append("police detail missing: %s" % detail_name)

	civilian.free()
	police.free()
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
