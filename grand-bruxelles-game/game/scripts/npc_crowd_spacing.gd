class_name NpcCrowdSpacing
extends RefCounted

var personal_space_m: float = 0.95
var release_space_m: float = 1.25
var detour_forward_m: float = 0.85
var detour_side_m: float = 0.72

func needs_spacing(agent_position: Vector3, peer_position: Vector3) -> bool:
	return _planar_distance(agent_position, peer_position) < maxf(0.1, personal_space_m)

func spacing_released(agent_position: Vector3, peer_position: Vector3) -> bool:
	return _planar_distance(agent_position, peer_position) >= maxf(personal_space_m, release_space_m)

func detour_target(agent_position: Vector3, destination: Vector3, peer_position: Vector3, seed: int, peer_seed: int, peer_destination: Vector3 = Vector3.INF) -> Vector3:
	var forward := _planar_direction(agent_position, destination)
	var lateral := Vector3(-forward.z, 0.0, forward.x)
	var side := _side_sign(agent_position, peer_position, seed, peer_seed)
	if peer_destination.is_finite():
		var peer_forward := _planar_direction(peer_position, peer_destination)
		if forward.dot(peer_forward) <= -0.5:
			side = _shared_pair_side_sign(seed, peer_seed)
	return agent_position + forward * maxf(0.2, detour_forward_m) + lateral * maxf(0.2, detour_side_m) * side

func _planar_direction(origin: Vector3, destination: Vector3) -> Vector3:
	var forward := destination - origin
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return forward.normalized()

func _shared_pair_side_sign(seed: int, peer_seed: int) -> float:
	var low := mini(seed, peer_seed)
	var high := maxi(seed, peer_seed)
	var mixed := absi(low * 1103515245 + high * 12345 + 97)
	return -1.0 if (mixed & 1) == 0 else 1.0

func _side_sign(agent_position: Vector3, peer_position: Vector3, seed: int, peer_seed: int) -> float:
	if seed != peer_seed:
		return -1.0 if seed < peer_seed else 1.0
	if not is_equal_approx(agent_position.x, peer_position.x):
		return -1.0 if agent_position.x < peer_position.x else 1.0
	if not is_equal_approx(agent_position.z, peer_position.z):
		return -1.0 if agent_position.z < peer_position.z else 1.0
	return -1.0 if (seed & 1) == 0 else 1.0

func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
