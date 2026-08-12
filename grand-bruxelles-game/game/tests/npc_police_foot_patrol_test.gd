extends SceneTree

const FootPatrol = preload("res://game/scripts/npc_police_foot_patrol.gd")

func _init() -> void:
	var deterministic_a := FootPatrol.new()
	deterministic_a.configure(120812, 1.0)
	var deterministic_b := FootPatrol.new()
	deterministic_b.configure(120812, 1.0)

	var station_a: Dictionary = deterministic_a.plan_segment("transit_hub", 3)
	var station_b: Dictionary = deterministic_b.plan_segment("transit_hub", 3)
	if station_a != station_b:
		_fail("same seed and segment must produce the same patrol plan")
		return

	if float(station_a.get("walk_speed_mps", 0.0)) < 0.85 or float(station_a.get("walk_speed_mps", 0.0)) > 1.55:
		_fail("foot-patrol walking speed must remain within a believable walking envelope")
		return
	if float(station_a.get("dwell_seconds", -1.0)) < 1.5 or float(station_a.get("dwell_seconds", -1.0)) > 11.0:
		_fail("patrol dwell must be bounded and non-mechanical")
		return
	if float(station_a.get("micro_pause_seconds", -1.0)) < 0.0 or float(station_a.get("micro_pause_seconds", -1.0)) > 2.5:
		_fail("micro-pauses must stay subtle")
		return

	var other := FootPatrol.new()
	other.configure(120913, 1.0)
	var station_other: Dictionary = other.plan_segment("transit_hub", 3)
	if is_equal_approx(float(station_a.get("walk_speed_mps", 0.0)), float(station_other.get("walk_speed_mps", 0.0))) and is_equal_approx(float(station_a.get("dwell_seconds", 0.0)), float(station_other.get("dwell_seconds", 0.0))):
		_fail("different officers must not synchronize pace and dwell")
		return

	var residential: Dictionary = deterministic_a.plan_segment("residential_street", 4)
	if float(residential.get("dwell_seconds", 0.0)) >= float(station_a.get("dwell_seconds", 0.0)) + 5.0:
		_fail("context variation must stay natural rather than producing extreme loitering")
		return
	if not residential.has("look_bias") or absf(float(residential["look_bias"])) > 1.0:
		_fail("look bias must be a normalized subtle variation")
		return

	print("NPC_POLICE_FOOT_PATROL_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error("NPC_POLICE_FOOT_PATROL_FAIL: %s" % message)
	quit(1)
