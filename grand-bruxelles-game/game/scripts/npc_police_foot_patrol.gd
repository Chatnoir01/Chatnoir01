extends RefCounted
class_name NpcPoliceFootPatrol

var _officer_seed: int = 1
var _pace_scale: float = 1.0

func configure(officer_seed: int, pace_scale: float = 1.0) -> void:
	_officer_seed = officer_seed if officer_seed != 0 else 1
	_pace_scale = clampf(pace_scale, 0.85, 1.15)

func plan_segment(context: String, segment_index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _segment_seed(context, segment_index)

	var base_speed := 1.16
	var base_dwell := 2.4
	match context:
		"transit_hub":
			base_speed = 1.04
			base_dwell = 4.0
		"commercial_street":
			base_speed = 1.10
			base_dwell = 3.1
		"residential_street":
			base_speed = 1.18
			base_dwell = 2.3
		"crossing_approach":
			base_speed = 0.98
			base_dwell = 2.0

	var gait_variation := rng.randf_range(-0.11, 0.12)
	var walk_speed := clampf((base_speed + gait_variation) * _pace_scale, 0.85, 1.55)
	var dwell_seconds := clampf(base_dwell + rng.randf_range(-0.65, 2.15), 1.5, 11.0)

	# Brief pauses make patrol movement read as observation rather than a metronomic loop.
	# They remain uncommon and short enough not to turn routine patrol into loitering.
	var micro_pause_seconds := 0.0
	if rng.randf() < 0.58:
		micro_pause_seconds = rng.randf_range(0.25, 1.65)

	return {
		"walk_speed_mps": walk_speed,
		"dwell_seconds": dwell_seconds,
		"micro_pause_seconds": micro_pause_seconds,
		"look_bias": rng.randf_range(-0.65, 0.65),
		"context": context,
		"segment_index": segment_index,
	}

func _segment_seed(context: String, segment_index: int) -> int:
	var mixed := _officer_seed * 1103515245 + segment_index * 2654435761 + _stable_string_hash(context)
	mixed = mixed ^ (mixed >> 17)
	mixed = mixed * 1099511628211
	mixed = mixed ^ (mixed >> 23)
	return absi(mixed) + 1

func _stable_string_hash(value: String) -> int:
	var result: int = 1469598103934665603
	for index in value.length():
		result = result ^ value.unicode_at(index)
		result = result * 1099511628211
	return result
