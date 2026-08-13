class_name NpcTransitQueue
extends RefCounted

var anchor := Vector3.ZERO
var queue_direction := Vector3(0.0, 0.0, 1.0)
var spacing_meters: float = 0.8
var max_queue_size: int = 8
var _passenger_ids: Array[int] = []

func configure(anchor_position: Vector3, direction: Vector3, spacing: float = 0.8, capacity: int = 8) -> void:
	anchor = anchor_position
	queue_direction = direction
	queue_direction.y = 0.0
	if queue_direction.length_squared() <= 0.0001:
		queue_direction = Vector3(0.0, 0.0, 1.0)
	else:
		queue_direction = queue_direction.normalized()
	spacing_meters = clampf(spacing, 0.65, 1.4)
	max_queue_size = maxi(capacity, 1)
	_passenger_ids.clear()

func join_queue(passenger_id: int) -> int:
	var existing: int = position_index_for(passenger_id)
	if existing >= 0:
		return existing
	if _passenger_ids.size() >= max_queue_size:
		return -1
	_passenger_ids.append(passenger_id)
	return _passenger_ids.size() - 1

func leave_queue(passenger_id: int) -> bool:
	var index: int = position_index_for(passenger_id)
	if index < 0:
		return false
	_passenger_ids.remove_at(index)
	return true

func position_index_for(passenger_id: int) -> int:
	for index in range(_passenger_ids.size()):
		if _passenger_ids[index] == passenger_id:
			return index
	return -1

func position_for(passenger_id: int) -> Vector3:
	var index: int = position_index_for(passenger_id)
	if index < 0:
		return anchor
	var longitudinal := anchor + queue_direction * (float(index) * spacing_meters)
	if index == 0:
		return longitudinal
	var lateral := Vector3(-queue_direction.z, 0.0, queue_direction.x)
	return longitudinal + lateral * _lateral_stagger_for(passenger_id, index)

func _lateral_stagger_for(passenger_id: int, index: int) -> float:
	if index <= 0:
		return 0.0
	var side := -1.0 if posmod(passenger_id + index, 2) == 0 else 1.0
	var magnitude_bucket := posmod(passenger_id * 7 + index, 3)
	var magnitude := 0.06 + float(magnitude_bucket) * 0.03
	return side * magnitude

func can_board(passenger_id: int, vehicle_capacity_remaining: int) -> bool:
	if vehicle_capacity_remaining <= 0:
		return false
	return position_index_for(passenger_id) == 0

func queue_size() -> int:
	return _passenger_ids.size()

func ordered_passenger_ids() -> Array[int]:
	return _passenger_ids.duplicate()
