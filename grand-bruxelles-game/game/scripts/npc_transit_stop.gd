class_name NpcTransitStop
extends RefCounted

var stop_id: String = ""
var anchor := Vector3.ZERO
var curb_direction := Vector3(1.0, 0.0, 0.0)
var platform_depth_direction := Vector3(0.0, 0.0, 1.0)
var door_offsets_meters := PackedFloat32Array()
var queue_spacing_meters: float = 0.85
var queue_capacity_per_door: int = 8

var _queues: Array[NpcTransitQueue] = []
var _passenger_to_door: Dictionary = {}
var _door_capacity_remaining := PackedInt32Array()
var _pending_alighting_per_door := PackedInt32Array()
var _boarding_open: bool = false

func configure(
	new_stop_id: String,
	stop_anchor: Vector3,
	new_curb_direction: Vector3,
	new_platform_depth_direction: Vector3,
	new_door_offsets_meters: PackedFloat32Array,
	queue_spacing: float = 0.85,
	queue_capacity: int = 8
) -> void:
	stop_id = new_stop_id
	anchor = stop_anchor
	curb_direction = _normalized_planar_or(new_curb_direction, Vector3(1.0, 0.0, 0.0))
	platform_depth_direction = _normalized_planar_or(new_platform_depth_direction, Vector3(0.0, 0.0, 1.0))
	if absf(curb_direction.dot(platform_depth_direction)) > 0.92:
		platform_depth_direction = Vector3(-curb_direction.z, 0.0, curb_direction.x)
	door_offsets_meters = new_door_offsets_meters.duplicate()
	if door_offsets_meters.is_empty():
		door_offsets_meters = PackedFloat32Array([0.0])
	queue_spacing_meters = clampf(queue_spacing, 0.65, 1.4)
	queue_capacity_per_door = maxi(queue_capacity, 1)
	_rebuild_queues()
	vehicle_departed()

func door_count() -> int:
	return _queues.size()

func door_anchor(door_index: int) -> Vector3:
	if door_index < 0 or door_index >= door_offsets_meters.size():
		return anchor
	return anchor + curb_direction * door_offsets_meters[door_index]

func join_waiting_passenger(passenger_id: int, preferred_door: int = -1) -> int:
	if passenger_id < 0 or _queues.is_empty():
		return -1
	if _passenger_to_door.has(passenger_id):
		return int(_passenger_to_door[passenger_id])

	var door_index: int = _select_door(preferred_door)
	if door_index < 0:
		return -1
	var slot: int = _queues[door_index].join_queue(passenger_id)
	if slot < 0:
		return -1
	_passenger_to_door[passenger_id] = door_index
	return door_index

func leave_waiting_passenger(passenger_id: int) -> bool:
	if not _passenger_to_door.has(passenger_id):
		return false
	var door_index: int = int(_passenger_to_door[passenger_id])
	_passenger_to_door.erase(passenger_id)
	if door_index < 0 or door_index >= _queues.size():
		return false
	return _queues[door_index].leave_queue(passenger_id)

func queue_target_for(passenger_id: int) -> Vector3:
	if not _passenger_to_door.has(passenger_id):
		return anchor
	var door_index: int = int(_passenger_to_door[passenger_id])
	return _queues[door_index].position_for(passenger_id)

func assigned_door_for(passenger_id: int) -> int:
	if not _passenger_to_door.has(passenger_id):
		return -1
	return int(_passenger_to_door[passenger_id])

func queue_for_door(door_index: int) -> NpcTransitQueue:
	if door_index < 0 or door_index >= _queues.size():
		return null
	return _queues[door_index]

func queue_size_for_door(door_index: int) -> int:
	var queue: NpcTransitQueue = queue_for_door(door_index)
	if queue == null:
		return 0
	return queue.queue_size()

func vehicle_arrived(capacity_per_door: PackedInt32Array, alighting_per_door: PackedInt32Array = PackedInt32Array()) -> void:
	_door_capacity_remaining.resize(_queues.size())
	_pending_alighting_per_door.resize(_queues.size())
	for door_index in range(_queues.size()):
		var capacity: int = 0
		if door_index < capacity_per_door.size():
			capacity = maxi(capacity_per_door[door_index], 0)
		_door_capacity_remaining[door_index] = capacity
		var alighting_count: int = 0
		if door_index < alighting_per_door.size():
			alighting_count = maxi(alighting_per_door[door_index], 0)
		_pending_alighting_per_door[door_index] = alighting_count
	_boarding_open = true

func vehicle_departed() -> void:
	_boarding_open = false
	_door_capacity_remaining.resize(_queues.size())
	_pending_alighting_per_door.resize(_queues.size())
	for door_index in range(_door_capacity_remaining.size()):
		_door_capacity_remaining[door_index] = 0
		_pending_alighting_per_door[door_index] = 0

func remaining_capacity_for_door(door_index: int) -> int:
	if door_index < 0 or door_index >= _door_capacity_remaining.size():
		return 0
	return _door_capacity_remaining[door_index]

func pending_alighting_for_door(door_index: int) -> int:
	if door_index < 0 or door_index >= _pending_alighting_per_door.size():
		return 0
	return _pending_alighting_per_door[door_index]

func register_disembarked(door_index: int) -> bool:
	if not _boarding_open:
		return false
	if door_index < 0 or door_index >= _pending_alighting_per_door.size():
		return false
	if _pending_alighting_per_door[door_index] <= 0:
		return false
	_pending_alighting_per_door[door_index] -= 1
	return true

func request_boarding(passenger_id: int) -> Dictionary:
	var result := {
		"allowed": false,
		"door_index": -1,
		"door_position": anchor,
		"reason": "not_waiting",
	}
	if not _passenger_to_door.has(passenger_id):
		return result
	var door_index: int = int(_passenger_to_door[passenger_id])
	result["door_index"] = door_index
	result["door_position"] = door_anchor(door_index)
	if not _boarding_open:
		result["reason"] = "boarding_closed"
		return result
	if pending_alighting_for_door(door_index) > 0:
		result["reason"] = "allow_disembark_first"
		return result
	if remaining_capacity_for_door(door_index) <= 0:
		result["reason"] = "door_full"
		return result
	var queue: NpcTransitQueue = _queues[door_index]
	if not queue.can_board(passenger_id, remaining_capacity_for_door(door_index)):
		result["reason"] = "wait_for_queue_head"
		return result

	_door_capacity_remaining[door_index] -= 1
	queue.leave_queue(passenger_id)
	_passenger_to_door.erase(passenger_id)
	result["allowed"] = true
	result["reason"] = "board"
	return result

func disembark_position_for(door_index: int, exit_sequence_index: int) -> Vector3:
	var base: Vector3 = door_anchor(door_index) + platform_depth_direction * 0.35
	if exit_sequence_index <= 0:
		return base + curb_direction * 0.75
	var side: float = -1.0 if exit_sequence_index % 2 == 0 else 1.0
	var rank: int = int((exit_sequence_index + 1) / 2.0)
	return base + curb_direction * (0.75 + float(rank) * 0.85) * side

func _select_door(preferred_door: int) -> int:
	if preferred_door >= 0 and preferred_door < _queues.size():
		if _queues[preferred_door].queue_size() < queue_capacity_per_door:
			return preferred_door

	var selected: int = -1
	var selected_size: int = 2147483647
	for door_index in range(_queues.size()):
		var size: int = _queues[door_index].queue_size()
		if size >= queue_capacity_per_door:
			continue
		if size < selected_size:
			selected = door_index
			selected_size = size
	return selected

func _rebuild_queues() -> void:
	_queues.clear()
	_passenger_to_door.clear()
	for door_index in range(door_offsets_meters.size()):
		var queue := NpcTransitQueue.new()
		queue.configure(door_anchor(door_index), platform_depth_direction, queue_spacing_meters, queue_capacity_per_door)
		_queues.append(queue)
	_door_capacity_remaining.resize(_queues.size())
	_pending_alighting_per_door.resize(_queues.size())

func _normalized_planar_or(value: Vector3, fallback: Vector3) -> Vector3:
	var planar := Vector3(value.x, 0.0, value.z)
	if planar.length_squared() <= 0.0001:
		return fallback
	return planar.normalized()
