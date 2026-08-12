extends SceneTree

const ScheduleResume = preload("res://game/scripts/npc_civilian_schedule_resume.gd")

func _init() -> void:
	var agent := NpcAgent.new()
	agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 42, Vector3.ZERO)
	var schedule := NpcDailySchedule.new()
	schedule.configure(NpcBehaviorModel.Role.CIVILIAN, 42, Vector3(0,0,0), Vector3(100,0,0), Vector3(25,0,40))
	var resume := ScheduleResume.new()
	resume.configure(schedule)

	var snapshot: Dictionary = resume.capture(agent, 19.0)
	var expected_activity: int = schedule.activity_for_hour(19.0)
	var expected_target: Vector3 = schedule.destination_for_hour(19.0)
	if int(snapshot.get("activity", -1)) != expected_activity:
		_fail("snapshot must preserve the precise scheduled activity")
		return

	agent.set_destination(Vector3(-50, 0, -50))
	if not resume.restore(agent, snapshot, 19.2):
		_fail("scheduled routine should restore after a short incident")
		return
	if agent.behavior.target_position != expected_target:
		_fail("restored civilian must return to the scheduled activity destination")
		return
	if int(agent.get_meta("civilian_schedule_activity", -1)) != expected_activity:
		_fail("restored agent must expose its scheduled activity to ambient/shop integrations")
		return

	var later := resume.capture(agent, 21.4)
	if not resume.restore(agent, later, 22.0):
		_fail("recovery crossing a schedule transition must select the current schedule safely")
		return
	if agent.behavior.target_position != schedule.destination_for_hour(22.0):
		_fail("long incidents must not send civilians back to an activity whose schedule already ended")
		return

	print("NPC_DAILY_SCHEDULE_RECOVERY_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error("NPC_DAILY_SCHEDULE_RECOVERY_FAIL: %s" % message)
	quit(1)
