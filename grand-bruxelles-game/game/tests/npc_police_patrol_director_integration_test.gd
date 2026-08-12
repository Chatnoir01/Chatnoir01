extends SceneTree

const PopulationDirector = preload("res://game/scripts/npc_population_director.gd")
const Agent = preload("res://game/scripts/npc_agent.gd")
const Behavior = preload("res://game/scripts/npc_behavior_model.gd")

func _init() -> void:
	var director := PopulationDirector.new()
	var officer := Agent.new()
	officer.set_spawn_context(Behavior.Role.POLICE, 120812, Vector3.ZERO)
	var base_speed := officer.behavior.preferred_speed
	if not director.register_agent(officer):
		_fail("police agent must register within the default budget")
		return

	var anchor := Vector3(6.0, 0.0, 0.0)
	var assigned: Dictionary = director.assign_police_patrol_segment(officer, "transit_hub", 2, anchor)
	if not bool(assigned.get("active", false)):
		_fail("director must activate a runtime patrol segment")
		return
	if officer.behavior.target_position != anchor:
		_fail("director must bind the patrol anchor to the live officer destination")
		return
	if not is_equal_approx(officer.behavior.preferred_speed, float(assigned.get("walk_speed_mps", 0.0))):
		_fail("live officer must consume the planned patrol walking speed")
		return
	if not officer.has_meta("police_patrol_look_bias"):
		_fail("director must expose look variation to the live officer for animation/visual consumption")
		return

	officer.position = anchor
	director.update_police_patrol_runtime(0.0)
	var arrived: Dictionary = director.police_patrol_runtime_snapshot(officer)
	if not officer.movement_held or not bool(arrived.get("movement_held", false)):
		_fail("live officer must dwell at a reached patrol anchor")
		return
	var hold_seconds := float(arrived.get("hold_remaining_seconds", 0.0))
	director.update_police_patrol_runtime(hold_seconds + 0.2)
	var completed: Dictionary = director.police_patrol_runtime_snapshot(officer)
	if officer.movement_held or not bool(completed.get("segment_complete", false)):
		_fail("live officer must release after the planned dwell/micro-pause")
		return
	if not is_equal_approx(officer.behavior.preferred_speed, base_speed):
		_fail("director must restore the officer base walking speed after patrol segment completion")
		return

	director.assign_police_patrol_segment(officer, "commercial_street", 3, Vector3(10.0, 0.0, 0.0))
	officer.report_police_incident(Vector3(2.0, 0.0, 0.0), 0.5, 77)
	director.update_police_patrol_runtime(0.1)
	var interrupted: Dictionary = director.police_patrol_runtime_snapshot(officer)
	if bool(interrupted.get("active", true)) or officer.movement_held:
		_fail("investigation must suspend routine patrol immediately")
		return
	if not is_equal_approx(officer.behavior.preferred_speed, base_speed):
		_fail("incident interruption must restore normal police movement speed")
		return

	director.unregister_agent(officer)
	if not director.police_patrol_runtime_snapshot(officer).is_empty():
		_fail("unregister must clear patrol runtime state")
		return

	officer.free()
	director.free()
	print("NPC_POLICE_PATROL_DIRECTOR_INTEGRATION_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error("NPC_POLICE_PATROL_DIRECTOR_INTEGRATION_FAIL: %s" % message)
	quit(1)
