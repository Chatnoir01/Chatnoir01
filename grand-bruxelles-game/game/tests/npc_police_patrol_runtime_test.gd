extends SceneTree

const PatrolRuntime = preload("res://game/scripts/npc_police_patrol_runtime.gd")

func _init() -> void:
	var runtime := PatrolRuntime.new()
	runtime.configure(120812, 1.0)

	var destination := Vector3(12.0, 0.0, -4.0)
	var plan: Dictionary = runtime.begin_segment("transit_hub", 5, destination)
	if not bool(plan.get("active", false)):
		_fail("begin_segment must activate a patrol segment")
		return
	if not plan.has("walk_speed_mps") or not plan.has("dwell_seconds") or not plan.has("micro_pause_seconds"):
		_fail("runtime must consume the full foot-patrol plan")
		return
	if Vector3(plan.get("destination", Vector3.ZERO)) != destination:
		_fail("runtime must preserve the patrol anchor destination")
		return

	var walking: Dictionary = runtime.sample(0.2, false, true)
	if bool(walking.get("movement_held", true)):
		_fail("officer must keep moving before reaching the anchor")
		return
	if float(walking.get("walk_speed_mps", 0.0)) < 0.85:
		_fail("runtime must expose the planned believable walking speed")
		return

	var arrived: Dictionary = runtime.sample(0.0, true, true)
	if not bool(arrived.get("movement_held", false)):
		_fail("reaching an anchor must start dwell/micro-pause hold")
		return
	var hold_seconds := float(arrived.get("hold_remaining_seconds", 0.0))
	var expected_hold := float(plan.get("dwell_seconds", 0.0)) + float(plan.get("micro_pause_seconds", 0.0))
	if not is_equal_approx(hold_seconds, expected_hold):
		_fail("anchor hold must consume dwell plus micro-pause exactly once")
		return

	var mid_hold: Dictionary = runtime.sample(maxf(hold_seconds * 0.5, 0.01), true, true)
	if hold_seconds > 0.02 and not bool(mid_hold.get("movement_held", false)):
		_fail("officer must remain held while observation dwell remains")
		return

	var finished: Dictionary = runtime.sample(hold_seconds + 0.1, true, true)
	if bool(finished.get("movement_held", true)) or not bool(finished.get("segment_complete", false)):
		_fail("runtime must release movement and complete the segment after its hold")
		return

	runtime.begin_segment("commercial_street", 6, Vector3(20.0, 0.0, 3.0))
	var interrupted: Dictionary = runtime.sample(0.1, false, false)
	if bool(interrupted.get("active", true)) or bool(interrupted.get("movement_held", true)):
		_fail("incident/investigation phases must immediately suspend routine patrol")
		return

	print("NPC_POLICE_PATROL_RUNTIME_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error("NPC_POLICE_PATROL_RUNTIME_FAIL: %s" % message)
	quit(1)
