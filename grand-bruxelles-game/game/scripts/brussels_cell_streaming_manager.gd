extends Node
class_name BrusselsCellStreamingManager

## Clean-room Brussels cell scheduler inspired by common distance-streaming patterns.
## It does not copy OpenLiberty/OpenRW code and never consumes GTA assets/data.
## Production geometry remains sourced from Brussels/UrbIS contracts.

signal cell_activation_requested(cell_id: String, descriptor: Dictionary)
signal cell_deactivation_requested(cell_id: String)
signal collision_tier_changed(cell_id: String, enabled: bool)

enum CellState { DORMANT, QUEUED, ACTIVE, COOLING }

@export var visual_load_radius_m := 650.0
@export var visual_unload_radius_m := 850.0
@export var collision_radius_m := 260.0
@export var lookahead_seconds := 4.0
@export var max_operations_per_tick := 2
@export var max_active_cells := 9

var _cells: Dictionary = {}
var _observer_position := Vector3.ZERO
var _observer_velocity := Vector3.ZERO
var _activation_count := 0
var _deactivation_count := 0
var _duplicate_activation_attempts := 0
var _collision_changes := 0
var _last_operations := 0

func register_cell_descriptor(cell_id: String, world_center: Vector3, source_bbox_lambert72: Rect2 = Rect2(), estimated_bytes: int = 0, runtime_paths: Dictionary = {}) -> bool:
    if cell_id.is_empty() or _cells.has(cell_id):
        return false
    _cells[cell_id] = {
        "cell_id": cell_id,
        "world_center": world_center,
        "source_bbox_lambert72": source_bbox_lambert72,
        "estimated_bytes": maxi(estimated_bytes, 0),
        "runtime_paths": runtime_paths.duplicate(true),
        "state": CellState.DORMANT,
        "collision_active": false,
        "priority": INF,
        "current_distance": INF,
        "predicted_distance": INF,
    }
    return true

func register_manifest_dict(manifest: Dictionary, world_center: Variant = null) -> bool:
    var cell_id := str(manifest.get("cell_id", ""))
    var bbox_raw: Variant = manifest.get("bbox", [])
    if cell_id.is_empty() or not bbox_raw is Array or bbox_raw.size() != 4:
        return false
    var min_e := float(bbox_raw[0])
    var min_n := float(bbox_raw[1])
    var max_e := float(bbox_raw[2])
    var max_n := float(bbox_raw[3])
    if max_e <= min_e or max_n <= min_n:
        return false
    var source_bbox := Rect2(min_e, min_n, max_e - min_e, max_n - min_n)
    var resolved_world_center := Vector3.ZERO
    if typeof(world_center) == TYPE_VECTOR3:
        resolved_world_center = world_center
    var runtime_paths: Dictionary = {}
    var runtime: Variant = manifest.get("runtime", {})
    if runtime is Dictionary:
        runtime_paths = {
            "geometry_file": str(runtime.get("geometry_file", "")),
            "network_file": str(runtime.get("network_file", "")),
        }
    return register_cell_descriptor(cell_id, resolved_world_center, source_bbox, 0, runtime_paths)

func update_observer(position: Vector3, velocity: Vector3) -> void:
    _observer_position = position
    _observer_velocity = velocity
    _recompute_priorities()
    _process_operations()
    _refresh_collisions()

func tick() -> void:
    _recompute_priorities()
    _process_operations()
    _refresh_collisions()

func _recompute_priorities() -> void:
    var predicted := _observer_position + _observer_velocity * lookahead_seconds
    for cell_id: String in _cells.keys():
        var cell: Dictionary = _cells[cell_id]
        var center: Vector3 = cell["world_center"]
        var current_distance := _flat_distance(_observer_position, center)
        var predicted_distance := _flat_distance(predicted, center)
        var priority := minf(current_distance, predicted_distance * 0.82)
        cell["current_distance"] = current_distance
        cell["predicted_distance"] = predicted_distance
        cell["priority"] = priority
        var state := int(cell["state"])
        if state == CellState.DORMANT and (current_distance <= visual_load_radius_m or predicted_distance <= visual_load_radius_m):
            cell["state"] = CellState.QUEUED
        elif state == CellState.ACTIVE and current_distance > visual_unload_radius_m and predicted_distance > visual_unload_radius_m:
            cell["state"] = CellState.COOLING
        elif state == CellState.COOLING and (current_distance <= visual_load_radius_m or predicted_distance <= visual_load_radius_m):
            cell["state"] = CellState.ACTIVE
        _cells[cell_id] = cell

func _process_operations() -> void:
    _last_operations = 0
    var queued := _ids_in_state(CellState.QUEUED)
    queued.sort_custom(func(a: String, b: String) -> bool: return get_priority(a) < get_priority(b))
    for cell_id: String in queued:
        if _last_operations >= max_operations_per_tick:
            break
        if get_active_cell_ids().size() >= max_active_cells:
            break
        _activate(cell_id)
        _last_operations += 1

    var cooling := _ids_in_state(CellState.COOLING)
    cooling.sort_custom(func(a: String, b: String) -> bool: return get_priority(a) > get_priority(b))
    for cell_id: String in cooling:
        if _last_operations >= max_operations_per_tick:
            break
        _deactivate(cell_id)
        _last_operations += 1

func _activate(cell_id: String) -> void:
    if not _cells.has(cell_id):
        return
    var cell: Dictionary = _cells[cell_id]
    if int(cell["state"]) == CellState.ACTIVE:
        _duplicate_activation_attempts += 1
        return
    cell["state"] = CellState.ACTIVE
    _cells[cell_id] = cell
    _activation_count += 1
    cell_activation_requested.emit(cell_id, cell.duplicate(true))

func _deactivate(cell_id: String) -> void:
    if not _cells.has(cell_id):
        return
    var cell: Dictionary = _cells[cell_id]
    if int(cell["state"]) == CellState.DORMANT:
        return
    if bool(cell["collision_active"]):
        cell["collision_active"] = false
        _collision_changes += 1
        collision_tier_changed.emit(cell_id, false)
    cell["state"] = CellState.DORMANT
    _cells[cell_id] = cell
    _deactivation_count += 1
    cell_deactivation_requested.emit(cell_id)

func _refresh_collisions() -> void:
    for cell_id: String in _cells.keys():
        var cell: Dictionary = _cells[cell_id]
        var should_collide := int(cell["state"]) == CellState.ACTIVE and float(cell["current_distance"]) <= collision_radius_m
        if bool(cell["collision_active"]) != should_collide:
            cell["collision_active"] = should_collide
            _collision_changes += 1
            _cells[cell_id] = cell
            collision_tier_changed.emit(cell_id, should_collide)

func _flat_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _ids_in_state(state: int) -> Array[String]:
    var result: Array[String] = []
    for cell_id: String in _cells.keys():
        if int((_cells[cell_id] as Dictionary)["state"]) == state:
            result.append(cell_id)
    return result

func get_active_cell_ids() -> Array[String]:
    return _ids_in_state(CellState.ACTIVE)

func get_queued_cell_ids() -> Array[String]:
    return _ids_in_state(CellState.QUEUED)

func is_collision_active(cell_id: String) -> bool:
    if not _cells.has(cell_id):
        return false
    return bool((_cells[cell_id] as Dictionary)["collision_active"])

func get_priority(cell_id: String) -> float:
    if not _cells.has(cell_id):
        return INF
    return float((_cells[cell_id] as Dictionary)["priority"])

func get_cell_descriptor(cell_id: String) -> Dictionary:
    if not _cells.has(cell_id):
        return {}
    return (_cells[cell_id] as Dictionary).duplicate(true)

func get_metrics() -> Dictionary:
    var estimated_active_bytes := 0
    for cell_id: String in get_active_cell_ids():
        estimated_active_bytes += int((_cells[cell_id] as Dictionary)["estimated_bytes"])
    return {
        "registered_cells": _cells.size(),
        "active_cells": get_active_cell_ids().size(),
        "queued_cells": get_queued_cell_ids().size(),
        "activation_count": _activation_count,
        "deactivation_count": _deactivation_count,
        "duplicate_activation_attempts": _duplicate_activation_attempts,
        "collision_changes": _collision_changes,
        "last_operations": _last_operations,
        "estimated_active_bytes": estimated_active_bytes,
    }
