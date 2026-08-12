class_name NpcCrowdReaction
extends RefCounted

const MAX_PROPAGATION_METERS := 50.0
const FLEE_THRESHOLD := 0.62
const AVOID_THRESHOLD := 0.30
const SHELTER_MULTIPLIER := 0.55

var variation_seed := 0

func configure(seed_value: int) -> void:
	variation_seed = seed_value

func reaction_for(agent_position: Vector3, stimulus_position: Vector3, stimulus_intensity: float, sheltered_or_occluded: bool) -> Dictionary:
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

	var action: StringName = &"observe"
	if intensity >= FLEE_THRESHOLD:
		action = &"flee"
	elif intensity >= AVOID_THRESHOLD:
		action = &"avoid"

	return {
		"action": action,
		"intensity": intensity,
		"distance_m": distance,
		"sheltered": sheltered_or_occluded,
	}
