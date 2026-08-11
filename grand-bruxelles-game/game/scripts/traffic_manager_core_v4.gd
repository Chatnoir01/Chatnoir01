extends "res://game/scripts/traffic_manager_core_v3.gd"

@export var density_enabled: bool = true
@export_range(0.0, 23.99, 0.05) var simulation_hour: float = 12.0
@export var auto_advance_simulation_time: bool = false
@export var simulated_minutes_per_real_second: float = 0.0
@export var density_refresh_interval_s: float = 2.0

const DENSITY_MODEL_SCRIPT := preload("res://game/scripts/traffic_density_model.gd")

var _density_model: RefCounted
var _base_max_vehicles: int = 0
var _corridor_anchors: Array = []
var _density_elapsed: float = 0.0
var _current_density_factor: float = 1.0
var _current_sector: String = "corridor"


func _ready() -> void:
    _density_model = DENSITY_MODEL_SCRIPT.new()
    _base_max_vehicles = max_vehicles
    _load_corridor_anchors()
    super._ready()
    _apply_density_now()
    print(
        "Grand Bruxelles traffic density: hour %.2f, sector %s, factor %.2f, target %d/%d vehicles" %
        [simulation_hour, _current_sector, _current_density_factor, max_vehicles, _base_max_vehicles]
    )


func _process(delta: float) -> void:
    if auto_advance_simulation_time and simulated_minutes_per_real_second > 0.0:
        simulation_hour = fposmod(
            simulation_hour + delta * simulated_minutes_per_real_second / 60.0,
            24.0
        )

    _density_elapsed += delta
    if _density_elapsed >= density_refresh_interval_s:
        _density_elapsed = 0.0
        _apply_density_now()

    super._process(delta)


func set_simulation_hour(hour: float) -> void:
    simulation_hour = fposmod(hour, 24.0)
    _apply_density_now()


func set_density_enabled(enabled: bool) -> void:
    density_enabled = enabled
    _apply_density_now()


func _load_corridor_anchors() -> void:
    _corridor_anchors.clear()
    var fallback := _read_json_dictionary(fallback_data_path)
    var corridor: Dictionary = fallback.get("corridor", {})
    var raw_anchors: Variant = corridor.get("anchors", [])
    if raw_anchors is Array:
        _corridor_anchors = (raw_anchors as Array).duplicate(true)


func _apply_density_now() -> void:
    if _density_model == null:
        return

    if not density_enabled:
        max_vehicles = _base_max_vehicles
        _current_density_factor = 1.0
        _current_sector = _density_model.call("nearest_sector", _corridor_anchors, _anchor_position())
        return

    var anchor := _anchor_position()
    var time_factor := float(_density_model.call("time_factor", simulation_hour))
    var capacity_factor := float(_density_model.call("local_capacity_factor", _roads, anchor))
    _current_density_factor = time_factor * capacity_factor
    _current_sector = str(_density_model.call("nearest_sector", _corridor_anchors, anchor))
    var target := int(_density_model.call(
        "target_vehicle_count",
        _base_max_vehicles,
        simulation_hour,
        _roads,
        anchor
    ))
    max_vehicles = target
    _trim_excess_traffic(target)


func _trim_excess_traffic(target: int) -> void:
    if _traffic_root == null:
        return
    var active: Array[Node] = []
    for child: Node in _traffic_root.get_children():
        if not child.is_queued_for_deletion():
            active.append(child)
    if active.size() <= target:
        return

    var anchor := _anchor_position()
    active.sort_custom(func(a: Node, b: Node) -> bool:
        if not a is Node3D or not b is Node3D:
            return false
        return (a as Node3D).global_position.distance_to(anchor) > (b as Node3D).global_position.distance_to(anchor)
    )
    for index: int in range(target, active.size()):
        active[index].queue_free()


func get_density_factor() -> float:
    return _current_density_factor


func get_density_sector() -> String:
    return _current_sector


func get_density_base_max_vehicles() -> int:
    return _base_max_vehicles


func get_density_target_vehicle_count() -> int:
    return max_vehicles
