class_name NpcCrowdReaction
extends RefCounted

const MAX_PROPAGATION_METERS := 50.0
const FLEE_THRESHOLD := 0.62
const AVOID_THRESHOLD := 0.30
const SHELTER_MULTIPLIER := 0.55
const REACTION_COOLDOWN_SECONDS := 1.25
const MEMORY_DECAY_SECONDS := 8.0
const EVENT_CELL_METERS := 3.0
const HABITUATION_FLOOR := 0.62

var variation_seed := 0
var _reaction_memory: Dictionary = {}

func configure(seed_value: int) -> void:
	variation_seed = seed_value
	_reaction_memory.clear()

func reaction_for(agent_position: Vector3, stimulus_position: Vector3, stimulus_intensity: float, sheltered_or_occluded: bool) -> Dictionary:
	return reaction_for_at(
		agent_position,
		stimulus_position,
		stimulus_intensity,
		sheltered_or_occluded,
		float(Time.get_ticks_msec()) / 1000.0
	)

func reaction_for_at(agent_position: Vector3, stimulus_position: Vector3, stimulus_intensity: float, sheltered_or_occluded: bool, now_seconds: float) -> Dictionary:
	_prune_memory(now_seconds)
	var distance := agent_position.distance_to(stimulus_position)
	var attenuation := clampf(1.0 - distance / MAX_PROPAGATION_METERS, 0.0, 1.0)
	var normalized_stimulus := clampf(stimulus_intensity, 0.0, 1.0)
	var intensity := normalized_stimulus * attenuation
	if sheltered_or_occluded:
		intensity *= SHELTER_MULTIPLIER

	# Small deterministic variation prevents perfectly synchronized crowd responses
	# without tying behavior to neighborhood, ethnicity, or other unsupported traits.
	var spatial_hash := int(round(agent_position.x * 10.0)) * 73856093
	spatial_hash ^= int(round(agent_position.z * 10.0)) * 19349663
	spatial_hash ^= variation_seed * 83492791
	var jitter := float(abs(spatial_hash) % 101) / 1000.0 - 0.05
	intensity = clampf(intensity + jitter, 0.0, 1.0)

	var event_key := _event_key(stimulus_position)
	var previous: Dictionary = _reaction_memory.get(event_key, {})
	var suppressed := false
	var repeat_count := 0
	if not previous.is_empty():
		var elapsed := maxf(0.0, now_seconds - float(previous.get("last_seen_s", -INF)))
		repeat_count = int(previous.get("repeat_count", 0))
		if elapsed < REACTION_COOLDOWN_SECONDS:
			suppressed = true
			intensity = 0.0
		else:
			repeat_count += 1
			var memory_age_ratio := clampf(elapsed / MEMORY_DECAY_SECONDS, 0.0, 1.0)
			var habituation := lerpf(HABITUATION_FLOOR, 1.0, memory_age_ratio)
			intensity *= habituation

	var action: StringName = &"observe"
	if suppressed:
		action = &"maintain"
	elif intensity >= FLEE_THRESHOLD:
		action = &"flee"
	elif intensity >= AVOID_THRESHOLD:
		action = &"avoid"

	_reaction_memory[event_key] = {
		"last_seen_s": now_seconds,
		"repeat_count": repeat_count,
		"last_action": action,
	}

	return {
		"action": action,
		"intensity": intensity,
		"distance_m": distance,
		"sheltered": sheltered_or_occluded,
		"suppressed": suppressed,
		"repeat_count": repeat_count,
	}

func clear_memory() -> void:
	_reaction_memory.clear()

func memory_size() -> int:
	return _reaction_memory.size()

func _event_key(stimulus_position: Vector3) -> StringName:
	var cell_x := int(floor(stimulus_position.x / EVENT_CELL_METERS))
	var cell_z := int(floor(stimulus_position.z / EVENT_CELL_METERS))
	return StringName("%d:%d" % [cell_x, cell_z])

func _prune_memory(now_seconds: float) -> void:
	var expired: Array[StringName] = []
	for raw_key: Variant in _reaction_memory.keys():
		var key := StringName(raw_key)
		var entry: Dictionary = _reaction_memory.get(key, {})
		if now_seconds - float(entry.get("last_seen_s", now_seconds)) > MEMORY_DECAY_SECONDS:
			expired.append(key)
	for key: StringName in expired:
		_reaction_memory.erase(key)
