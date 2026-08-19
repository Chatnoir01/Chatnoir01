extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/midi_ambient_npc_visual_runtime.gd")
const LEGACY_NAMES := ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]
const BANNED_CIVILIAN_ASSET := "res://assets/characters/player_character.glb"

func _init() -> void:
	var red_findings: Array[String] = []
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
		push_error("MIDI_REALISTIC_AUTHORED_NPCS_RED_FAIL: current Midi pedestrian did not bridge; regression path not exercised")
		quit(2)
		return

	# Current production explicitly leaves the legacy geometry visible and starts it at the far LOD range.
	for legacy_name: String in LEGACY_NAMES:
		var legacy := person.get_node_or_null(legacy_name) as GeometryInstance3D
		if legacy != null and legacy.visible and legacy.visibility_range_begin > 0.0:
			red_findings.append("legacy cuboid authorized from %.1fm: %s" % [legacy.visibility_range_begin, legacy_name])

	var contract: Dictionary = runtime.truth_contract()
	if bool(contract.get("legacy_primitives_far", false)):
		red_findings.append("truth contract still authorizes legacy primitives at far LOD")
	if str(contract.get("legacy_body_fallback", "")) != "retired":
		red_findings.append("truth contract does not retire cuboid fallback")

	# The authored roster runtime/module are intentionally absent on current main; this is also part of the RED.
	if not FileAccess.file_exists("res://game/scripts/midi_realistic_authored_npc_runtime.gd"):
		red_findings.append("realistic authored NPC roster runtime missing")
	if not FileAccess.file_exists("res://data/runtime/modules/midi_realistic_authored_npcs.json"):
		red_findings.append("realistic authored NPC runtime module missing")

	# Permanent product guard: the existing player KayKit may exist, but it is forbidden as the civilian roster.
	if FileAccess.file_exists(BANNED_CIVILIAN_ASSET):
		print("MIDI_REALISTIC_AUTHORED_NPCS_GUARD: player asset exists but is forbidden as civilian roster")

	scene.free()
	runtime.free()

	if red_findings.is_empty():
		push_error("MIDI_REALISTIC_AUTHORED_NPCS_RED_FAIL: expected production realism defects were not reproduced")
		quit(2)
		return

	for finding in red_findings:
		print("MIDI_REALISTIC_AUTHORED_NPCS_RED_EXPECTED: %s" % finding)
	print("MIDI_REALISTIC_AUTHORED_NPCS_RED_OK")
	quit(0)
