class_name NpcPedestrianContext
extends RefCounted

enum CrossingSignal {
	NONE,
	GREEN,
	RED,
}

enum PedestrianIntent {
	CONTINUE,
	WAIT_AT_CURB,
	CROSS,
	WAIT_FOR_TRANSIT,
	BOARD_TRANSIT,
}

var variation_seed: int = 0
var preferred_speed: float = 1.35
var curb_patience_seconds: float = 6.0
var transit_patience_seconds: float = 180.0
var transit_boarding_dwell_seconds: float = 2.5

func configure(seed_value: int, base_speed: float = 1.35) -> void:
	variation_seed = seed_value
	preferred_speed = clampf(base_speed, 0.75, 1.75)
	curb_patience_seconds = lerpf(3.5, 11.0, _unit(17))
	transit_patience_seconds = lerpf(75.0, 360.0, _unit(29))
	transit_boarding_dwell_seconds = lerpf(1.8, 3.8, _unit(43))

func crossing_intent(signal_value: int, traffic_gap_safe: bool, _waiting_seconds: float) -> int:
	if signal_value == CrossingSignal.GREEN:
		return PedestrianIntent.CROSS
	if signal_value == CrossingSignal.RED:
		return PedestrianIntent.WAIT_AT_CURB
	if traffic_gap_safe:
		return PedestrianIntent.CROSS
	return PedestrianIntent.WAIT_AT_CURB

func curb_recheck_interval_seconds(attempt_index: int) -> float:
	var attempt: int = maxi(attempt_index, 0)
	var salt: int = 71 + attempt * 19
	var individual_base: float = lerpf(0.72, 1.42, _unit(salt))
	var patience_bias: float = remap(curb_patience_seconds, 3.5, 11.0, 0.90, 1.10)
	return clampf(individual_base * patience_bias, 0.55, 1.65)

func should_recheck_crossing_gap(elapsed_since_check_seconds: float, attempt_index: int) -> bool:
	return maxf(elapsed_since_check_seconds, 0.0) >= curb_recheck_interval_seconds(attempt_index)

func transit_intent(vehicle_arrived: bool, has_capacity: bool, waiting_seconds: float) -> int:
	var elapsed_wait: float = maxf(waiting_seconds, 0.0)
	if vehicle_arrived and has_capacity and elapsed_wait >= transit_boarding_dwell_seconds:
		return PedestrianIntent.BOARD_TRANSIT
	if elapsed_wait <= transit_patience_seconds:
		return PedestrianIntent.WAIT_FOR_TRANSIT
	return PedestrianIntent.CONTINUE

func idle_duration_seconds(sequence_index: int) -> float:
	var mix: int = absi(variation_seed * 31 + sequence_index * 73)
	return lerpf(1.2, 8.5, float(mix % 1000) / 1000.0)

func idle_phase_offset_seconds(cycle_seconds: float) -> float:
	var cycle: float = maxf(cycle_seconds, 0.0)
	if cycle <= 0.0:
		return 0.0
	return cycle * _unit(53)

func idle_variant_index(sequence_index: int, variant_count: int) -> int:
	if variant_count <= 0:
		return -1
	var mixed: int = absi(variation_seed * 97 + sequence_index * 193 + 61)
	return mixed % variant_count

func lateral_personal_space_meters(crowd_density: float) -> float:
	var density: float = clampf(crowd_density, 0.0, 1.0)
	var relaxed: float = lerpf(0.55, 0.95, _unit(41))
	return lerpf(relaxed, 0.28, density)

func _unit(salt: int) -> float:
	var mixed: int = absi(variation_seed * 1103515245 + salt * 12345)
	return float(mixed % 10000) / 10000.0
