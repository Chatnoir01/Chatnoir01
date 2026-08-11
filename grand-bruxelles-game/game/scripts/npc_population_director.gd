class_name NpcPopulationDirector
extends Node

@export var civilian_budget: int = 48
@export var police_budget: int = 10
@export var activation_distance: float = 110.0
@export var despawn_distance: float = 180.0

var _civilians: Array[NpcAgent] = []
var _police: Array[NpcAgent] = []
var _pool: Array[NpcAgent] = []
var observer_position := Vector3.ZERO

func set_observer_position(world_position: Vector3) -> void:
	observer_position = world_position
	for agent in _civilians:
		if is_instance_valid(agent):
			agent.set_observer_position(world_position)
	for agent in _police:
		if is_instance_valid(agent):
			agent.set_observer_position(world_position)

func register_agent(agent: NpcAgent) -> bool:
	if not is_instance_valid(agent):
		return false
	agent.despawn_distance = despawn_distance
	agent.set_observer_position(observer_position)
	if agent.role == NpcBehaviorModel.Role.POLICE:
		if _police.size() >= max(police_budget, 0):
			_pool_agent(agent)
			return false
		if not _police.has(agent):
			_police.append(agent)
	else:
		if _civilians.size() >= max(civilian_budget, 0):
			_pool_agent(agent)
			return false
		if not _civilians.has(agent):
			_civilians.append(agent)
	return true

func unregister_agent(agent: NpcAgent) -> void:
	_civilians.erase(agent)
	_police.erase(agent)
	_pool.erase(agent)

func broadcast_event(world_position: Vector3, intensity: float, radius: float) -> int:
	if radius <= 0.0 or intensity <= 0.0:
		return 0
	var affected := 0
	var radius_sq := radius * radius
	for agent in _active_agents():
		if not is_instance_valid(agent) or not agent.active:
			continue
		if agent.global_position.distance_squared_to(world_position) <= radius_sq:
			agent.react_to_event(intensity, world_position)
			affected += 1
	return affected

func collect_inactive_agents() -> int:
	var collected := 0
	for agent in _active_agents().duplicate():
		if not is_instance_valid(agent):
			unregister_agent(agent)
			continue
		if not agent.active:
			_civilians.erase(agent)
			_police.erase(agent)
			if not _pool.has(agent):
				_pool.append(agent)
			collected += 1
	return collected

func acquire_pooled_agent(role: NpcBehaviorModel.Role, seed_value: int, spawn_position: Vector3) -> NpcAgent:
	if _pool.is_empty():
		return null
	var agent := _pool.pop_back()
	if not is_instance_valid(agent):
		return acquire_pooled_agent(role, seed_value, spawn_position)
	agent.role = role
	agent.variation_seed = seed_value
	agent.reactivate(spawn_position)
	register_agent(agent)
	return agent

func get_counts() -> Dictionary:
	return {
		"civilians": _civilians.size(),
		"police": _police.size(),
		"pooled": _pool.size(),
		"civilian_budget": civilian_budget,
		"police_budget": police_budget,
	}

func _active_agents() -> Array[NpcAgent]:
	var result: Array[NpcAgent] = []
	result.append_array(_civilians)
	result.append_array(_police)
	return result

func _pool_agent(agent: NpcAgent) -> void:
	agent.active = false
	agent.visible = false
	agent.set_physics_process(false)
	if not _pool.has(agent):
		_pool.append(agent)
