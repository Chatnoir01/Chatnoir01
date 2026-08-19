extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/midi_ambient_npc_visual_runtime.gd")
const LEGACY_NAMES := ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]


func _init() -> void:
	var failures: Array[String] = []
	var runtime := RUNTIME_SCRIPT.new()
	var scene := Node3D.new()
	var urban_life := Node3D.new()
	urban_life.name = "MidiUrbanLife"
	scene.add_child(urban_life)

	var person := Node3D.new()
	person.name = "AmbientPedestrian_00"
	person.add_to_group("ambient_pedestrian")
	urban_life.add_child(person)
	for legacy_name: String in LEGACY_NAMES:
		var legacy := MeshInstance3D.new()
		legacy.name = legacy_name
		legacy.mesh = BoxMesh.new()
		legacy.visible = true
		person.add_child(legacy)

	var result: Dictionary = runtime.bridge_scene(scene)
	if int(result.get("bridged", 0)) != 1:
		failures.append("ambient pedestrian should receive one profiled visual proxy")
	if int(result.get("lod_legacy_visible", -1)) != 0:
		failures.append("legacy cuboid pieces must be hidden immediately after bridge")

	var proxy := person.get_node_or_null("ProfiledNpcProxy") as Node3D
	if proxy == null:
		failures.append("ProfiledNpcProxy is required")
	else:
		var visual := proxy.get_node_or_null("VisualUpgrade") as Node3D
		if visual == null:
			failures.append("profiled proxy should use HumanoidVisual")
		else:
			var sample_mesh := MeshInstance3D.new()
			sample_mesh.name = "DistanceBudgetWitness"
			sample_mesh.mesh = CapsuleMesh.new()
			visual.add_child(sample_mesh)
			runtime.set_profiled_visuals_enabled(scene, true)
			if not "WEB_LOD_SWITCH_DISTANCE_M" in RUNTIME_SCRIPT:
				failures.append("runtime must expose a dedicated Web profiled-human distance budget")
			elif sample_mesh.visibility_range_end < float(RUNTIME_SCRIPT.WEB_LOD_SWITCH_DISTANCE_M):
				failures.append("profiled humanoid should remain visible through the Web distance budget")

	_assert_legacy_hidden(failures, person, "enabled profiled path")

	runtime.set_profiled_visuals_enabled(scene, false)
	if proxy != null and proxy.visible:
		failures.append("disabling profiled visuals should hide the proxy")
	_assert_legacy_hidden(failures, person, "disabled profiled path")

	# A caller must not be able to accidentally resurrect the retired box/sphere body.
	runtime._set_legacy_visuals(person, true)
	_assert_legacy_hidden(failures, person, "explicit legacy enable attempt")

	var contract: Dictionary = runtime.truth_contract()
	if "legacy cuboid primitives never rendered" not in str(contract.get("distance_lod", "")):
		failures.append("truth contract must state that cuboid primitives never render")
	if str(contract.get("legacy_body_fallback", "")) != "retired":
		failures.append("truth contract must retire the legacy body fallback")
	if bool(contract.get("legacy_primitives_far", true)):
		failures.append("truth contract must forbid legacy primitives at far distance")

	scene.free()
	runtime.free()

	if failures.is_empty():
		print("MIDI_AMBIENT_NPC_VISUAL_RUNTIME_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("MIDI_AMBIENT_NPC_VISUAL_RUNTIME_FAIL: %s" % failure)
		quit(1)


func _assert_legacy_hidden(failures: Array[String], person: Node3D, context: String) -> void:
	for legacy_name: String in LEGACY_NAMES:
		var legacy := person.get_node_or_null(legacy_name) as GeometryInstance3D
		if legacy != null and legacy.visible:
			failures.append("%s: %s must stay hidden" % [context, legacy_name])
