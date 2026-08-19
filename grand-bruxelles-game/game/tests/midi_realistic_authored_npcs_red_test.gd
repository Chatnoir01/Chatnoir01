extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/midi_ambient_npc_visual_runtime.gd")
const LEGACY_NAMES := ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]
const BANNED_CIVILIAN_ASSET := "res://assets/characters/player_character.glb"

func _init() -> void:
	var failures: Array[String] = []
	var runtime := RUNTIME_SCRIPT.new()
	var scene := Node3D.new()
	var urban_life := Node3D.new()
	urban_life.name = "MidiUrbanLife"
	scene.add_child(urban_life)

	var person := Node3D.new()
	person.name = "AmbientPedestrian_RED_00"
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
		failures.append("current Midi pedestrian must bridge so the real regression path is exercised")

	# Reproduce the current production defect: the legacy box body can return at distance.
	person.global_position = Vector3(200.0, 0.0, 0.0)
	runtime.set_camera_position_for_test(Vector3.ZERO)
	runtime.update_lod_for_test(scene)
	for legacy_name: String in LEGACY_NAMES:
		var legacy := person.get_node_or_null(legacy_name) as GeometryInstance3D
		if legacy != null and legacy.visible:
			failures.append("legacy cuboid resurrects at far LOD: %s" % legacy_name)

	var contract: Dictionary = runtime.truth_contract()
	if bool(contract.get("legacy_primitives_far", false)):
		failures.append("truth contract still authorizes legacy primitives at far LOD")
	if str(contract.get("legacy_body_fallback", "")) != "retired":
		failures.append("truth contract must retire cuboid fallback")

	# The authored roster runtime is intentionally absent on current main; this is part of the RED.
	if not FileAccess.file_exists("res://game/scripts/midi_realistic_authored_npc_runtime.gd"):
		failures.append("realistic authored NPC roster runtime missing")
	if not FileAccess.file_exists("res://data/runtime/modules/midi_realistic_authored_npcs.json"):
		failures.append("realistic authored NPC runtime module missing")

	# Guard the product rule before implementation: the player KayKit asset cannot become the civilian roster.
	if FileAccess.file_exists(BANNED_CIVILIAN_ASSET):
		print("MIDI_REALISTIC_AUTHORED_NPCS_GUARD: player asset exists but is forbidden as civilian roster")

	scene.free()
	runtime.free()

	if failures.is_empty():
		push_error("MIDI_REALISTIC_AUTHORED_NPCS_RED_FAIL: test unexpectedly passed; RED defect was not reproduced")
		quit(2)
	else:
		for failure in failures:
			print("MIDI_REALISTIC_AUTHORED_NPCS_RED_EXPECTED: %s" % failure)
		print("MIDI_REALISTIC_AUTHORED_NPCS_RED_OK")
		quit(0)
