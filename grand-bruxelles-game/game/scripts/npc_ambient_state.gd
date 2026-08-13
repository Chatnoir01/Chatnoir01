class_name NpcAmbientState
extends RefCounted

enum State {
	WALK,
	IDLE,
	LOOK_AROUND,
	CHECK_PHONE,
	SOCIAL_PAUSE,
	WAIT_TRANSIT,
	BOARDING,
}

var variation_seed: int = 0
var current_state: int = State.WALK
var sequence_index: int = 0

func configure(seed_value: int) -> void:
	variation_seed = seed_value
	sequence_index = 0
	current_state = State.WALK

func set_transit_context(waiting: bool, boarding: bool) -> int:
	if boarding:
		current_state = State.BOARDING
	elif waiting:
		current_state = State.WAIT_TRANSIT
	elif current_state == State.WAIT_TRANSIT or current_state == State.BOARDING:
		current_state = State.WALK
	return current_state

func advance(is_raining: bool, crowd_is_dense: bool, requested_sequence_index: int = -1, has_social_partner: bool = false) -> int:
	if current_state == State.WAIT_TRANSIT or current_state == State.BOARDING:
		return current_state
	if requested_sequence_index >= 0:
		sequence_index = requested_sequence_index
	else:
		sequence_index += 1

	var cycle: Array[int] = [State.WALK, State.IDLE, State.LOOK_AROUND, State.CHECK_PHONE, State.SOCIAL_PAUSE]
	var offset: int = absi(variation_seed) % cycle.size()
	var index: int = (sequence_index + offset) % cycle.size()
	current_state = cycle[index]
	if current_state == State.SOCIAL_PAUSE and not has_social_partner:
		current_state = State.LOOK_AROUND
	if crowd_is_dense and current_state == State.SOCIAL_PAUSE:
		current_state = State.LOOK_AROUND
	if is_raining and current_state == State.CHECK_PHONE and _unit(71) < 0.6:
		current_state = State.IDLE
	return current_state

func transit_wait_animation_tag(queue_index: int, is_raining: bool, cycle_index: int = 0) -> StringName:
	var safe_queue_index: int = maxi(queue_index, 0)
	var mixed: int = absi(variation_seed * 97 + safe_queue_index * 43 + cycle_index * 181 + 17)
	var variant: int = mixed % 4
	if safe_queue_index == 0 and mixed % 3 == 0:
		return &"wait_look_for_vehicle"
	if is_raining and variant == 2:
		return &"wait_shift_weight"
	match variant:
		0:
			return &"wait_still"
		1:
			return &"wait_look_for_vehicle"
		2:
			return &"wait_check_phone"
		_:
			return &"wait_shift_weight"

func state_duration_seconds(salt: int = 0) -> float:
	match current_state:
		State.WALK:
			return lerpf(4.0, 11.5, _unit(101 + salt))
		State.IDLE:
			return lerpf(1.2, 7.5, _unit(103 + salt))
		State.LOOK_AROUND:
			return lerpf(1.0, 4.8, _unit(107 + salt))
		State.CHECK_PHONE:
			return lerpf(2.0, 10.0, _unit(109 + salt))
		State.SOCIAL_PAUSE:
			return lerpf(2.5, 12.0, _unit(113 + salt))
		State.WAIT_TRANSIT:
			return lerpf(4.0, 12.0, _unit(127 + salt))
		State.BOARDING:
			return lerpf(1.0, 3.5, _unit(131 + salt))
	return 1.0

func movement_scale() -> float:
	if current_state == State.WALK:
		return 1.0
	if current_state == State.BOARDING:
		return 0.35
	return 0.0

func animation_tag() -> StringName:
	match current_state:
		State.WALK:
			return &"walk"
		State.IDLE:
			return &"idle"
		State.LOOK_AROUND:
			return &"look_around"
		State.CHECK_PHONE:
			return &"check_phone"
		State.SOCIAL_PAUSE:
			return &"social_pause"
		State.WAIT_TRANSIT:
			return transit_wait_animation_tag(0, false, sequence_index)
		State.BOARDING:
			return &"boarding"
	return &"idle"

func _unit(salt: int) -> float:
	var mixed: int = absi(variation_seed * 1103515245 + salt * 12345)
	return float(mixed % 10000) / 10000.0
