class_name NpcCivilianScheduleResume
extends RefCounted

var schedule: NpcDailySchedule = null

func configure(new_schedule: NpcDailySchedule) -> void:
	schedule = new_schedule

func capture(agent: NpcAgent, hour: float) -> Dictionary:
	if agent == null or schedule == null or agent.role != NpcBehaviorModel.Role.CIVILIAN:
		return {}
	return {
		"activity": schedule.activity_for_hour(hour),
		"destination": schedule.destination_for_hour(hour),
		"captured_hour": fposmod(hour, 24.0),
		"next_transition_hour": schedule.next_transition_hour(hour),
	}

func restore(agent: NpcAgent, snapshot: Dictionary, current_hour: float) -> bool:
	if agent == null or schedule == null or agent.role != NpcBehaviorModel.Role.CIVILIAN or snapshot.is_empty():
		return false
	if agent.transit_state in [NpcAgent.TransitState.BOARDING, NpcAgent.TransitState.ONBOARD, NpcAgent.TransitState.DISEMBARKING]:
		return false

	var now := fposmod(current_hour, 24.0)
	var captured_activity := int(snapshot.get("activity", -1))
	var next_transition := float(snapshot.get("next_transition_hour", now))
	var target_activity := captured_activity
	var target_destination_value: Variant = snapshot.get("destination", schedule.destination_for_hour(now))

	var transition_crossed := false
	var captured_hour := float(snapshot.get("captured_hour", now))
	if next_transition >= 24.0:
		var unfolded_now := now + (24.0 if now < captured_hour else 0.0)
		transition_crossed = unfolded_now >= next_transition
	else:
		transition_crossed = now >= next_transition and captured_hour < next_transition

	if transition_crossed or captured_activity != schedule.activity_for_hour(now):
		target_activity = schedule.activity_for_hour(now)
		target_destination_value = schedule.destination_for_hour(now)

	if not target_destination_value is Vector3:
		return false
	agent.set_destination(target_destination_value as Vector3)
	agent.set_meta("civilian_schedule_activity", target_activity)
	agent.set_meta("civilian_schedule_next_transition_hour", schedule.next_transition_hour(now))
	return true
