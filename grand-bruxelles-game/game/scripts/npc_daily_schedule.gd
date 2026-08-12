class_name NpcDailySchedule
extends RefCounted

enum Activity {
	HOME,
	COMMUTE,
	WORK_OR_STUDY,
	SHOP,
	LEISURE,
	PATROL,
	BREAK,
}

var role: NpcBehaviorModel.Role = NpcBehaviorModel.Role.CIVILIAN
var seed_value: int = 0
var home_anchor := Vector3.ZERO
var primary_anchor := Vector3.ZERO
var secondary_anchor := Vector3.ZERO

func configure(new_role: NpcBehaviorModel.Role, seed: int, home: Vector3, primary: Vector3, secondary: Vector3) -> void:
	role = new_role
	seed_value = seed
	home_anchor = home
	primary_anchor = primary
	secondary_anchor = secondary

func activity_for_hour(hour: float) -> Activity:
	var h := fposmod(hour, 24.0)
	if role == NpcBehaviorModel.Role.POLICE:
		return _police_activity(h)
	return _civilian_activity(h)

func destination_for_hour(hour: float) -> Vector3:
	var activity := activity_for_hour(hour)
	match activity:
		Activity.HOME:
			return home_anchor
		Activity.COMMUTE, Activity.WORK_OR_STUDY, Activity.PATROL:
			return primary_anchor
		Activity.SHOP, Activity.LEISURE, Activity.BREAK:
			return secondary_anchor
		_:
			return home_anchor

func next_transition_hour(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var transitions: Array[float]
	if role == NpcBehaviorModel.Role.POLICE:
		transitions = [6.0, 14.0, 22.0]
	else:
		var offset := _civilian_offset()
		transitions = [6.5 + offset, 8.0 + offset, 16.5 + offset, 18.0 + offset, 21.5 + offset]
	for transition in transitions:
		if transition > h:
			return transition
	return transitions[0] + 24.0

func _civilian_activity(hour: float) -> Activity:
	var offset := _civilian_offset()
	if hour < 6.5 + offset:
		return Activity.HOME
	if hour < 8.0 + offset:
		return Activity.COMMUTE
	if hour < 16.5 + offset:
		return Activity.WORK_OR_STUDY
	if hour < 18.0 + offset:
		return Activity.COMMUTE
	if hour < 21.5 + offset:
		return Activity.SHOP if abs(seed_value) % 2 == 0 else Activity.LEISURE
	return Activity.HOME

func _police_activity(hour: float) -> Activity:
	var shift := int(floor(hour / 8.0))
	var assigned_shift: int = int(abs(seed_value)) % 3
	if shift == assigned_shift:
		var within_shift := fposmod(hour, 8.0)
		return Activity.BREAK if within_shift >= 3.75 and within_shift < 4.25 else Activity.PATROL
	return Activity.HOME

func _civilian_offset() -> float:
	return float((abs(seed_value) % 7) - 3) * 0.1
