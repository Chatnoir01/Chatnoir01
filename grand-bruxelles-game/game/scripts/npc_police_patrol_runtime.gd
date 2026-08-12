class_name NpcPolicePatrolRuntime
extends RefCounted

var _planner := NpcPoliceFootPatrol.new()
var _active_plan: Dictionary = {}
var _active := false
var _arrival_hold_started := false
var _hold_remaining_seconds := 0.0
var _segment_complete := false

func configure(officer_seed: int, pace_scale: float = 1.0) -> void:
	_planner.configure(officer_seed, pace_scale)
	_reset_runtime()

func begin_segment(context: String, segment_index: int, destination: Vector3) -> Dictionary:
	var planned: Dictionary = _planner.plan_segment(context, segment_index)
	_active_plan = planned.duplicate(true)
	_active_plan["destination"] = destination
	_active = true
	_arrival_hold_started = false
	_hold_remaining_seconds = 0.0
	_segment_complete = false
	return _snapshot()

func sample(delta_seconds: float, arrived_at_anchor: bool, patrol_active: bool) -> Dictionary:
	if not patrol_active:
		_reset_runtime()
		return _snapshot()
	if not _active:
		return _snapshot()

	if not arrived_at_anchor:
		return _snapshot()

	if not _arrival_hold_started:
		_arrival_hold_started = true
		_hold_remaining_seconds = maxf(
			float(_active_plan.get("dwell_seconds", 0.0)) + float(_active_plan.get("micro_pause_seconds", 0.0)),
			0.0
		)

	_hold_remaining_seconds = maxf(_hold_remaining_seconds - maxf(delta_seconds, 0.0), 0.0)
	if _hold_remaining_seconds <= 0.0:
		_active = false
		_segment_complete = true
	return _snapshot()

func cancel() -> void:
	_reset_runtime()

func is_active() -> bool:
	return _active

func _snapshot() -> Dictionary:
	var result: Dictionary = _active_plan.duplicate(true)
	result["active"] = _active
	result["movement_held"] = _active and _arrival_hold_started and _hold_remaining_seconds > 0.0
	result["hold_remaining_seconds"] = _hold_remaining_seconds
	result["segment_complete"] = _segment_complete
	if not result.has("walk_speed_mps"):
		result["walk_speed_mps"] = 0.0
	if not result.has("dwell_seconds"):
		result["dwell_seconds"] = 0.0
	if not result.has("micro_pause_seconds"):
		result["micro_pause_seconds"] = 0.0
	if not result.has("look_bias"):
		result["look_bias"] = 0.0
	if not result.has("destination"):
		result["destination"] = Vector3.ZERO
	return result

func _reset_runtime() -> void:
	_active_plan = {}
	_active = false
	_arrival_hold_started = false
	_hold_remaining_seconds = 0.0
	_segment_complete = false
