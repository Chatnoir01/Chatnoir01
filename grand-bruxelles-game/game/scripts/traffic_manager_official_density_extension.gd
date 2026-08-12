extends "res://game/scripts/traffic_manager_tow_extension.gd"
class_name TrafficManagerOfficialDensityExtension

@export var official_density_enabled: bool = true
@export_file("*.json") var official_density_snapshot_path: String = "res://data/traffic/brussels_mobility_snapshot.json"
@export var official_density_radius_m: float = 1800.0
@export_range(0.0, 1.0, 0.01) var official_density_blend_weight: float = 0.72

var _official_density_loaded: bool = false
var _current_official_density_available: bool = false
var _current_official_density_factor: float = 1.0
var _current_official_density_sample_count: int = 0
var _current_official_density_nearest_distance_m: float = INF
var _current_official_density_sensor_ids := PackedStringArray()

func _ready() -> void:
    super._ready()
    reload_official_density_calibration()
    _apply_density_now()
    if auto_spawn_runtime:
        _replenish_traffic()

func reload_official_density_calibration() -> bool:
    _official_density_loaded = false
    _reset_current_official_calibration()
    if _density_model == null:
        return false
    if not official_density_enabled:
        _density_model.call("clear_official_snapshot")
        return false
    var snapshot := _read_json_dictionary(official_density_snapshot_path)
    if snapshot.is_empty():
        _density_model.call("clear_official_snapshot")
        push_warning("Official Brussels Mobility traffic calibration snapshot is unavailable: %s" % official_density_snapshot_path)
        return false
    _official_density_loaded = bool(_density_model.call(
        "configure_official_snapshot",
        snapshot,
        maxf(1.0, official_density_radius_m),
        clampf(official_density_blend_weight, 0.0, 1.0)
    ))
    if not _official_density_loaded:
        push_warning("Official Brussels Mobility traffic calibration snapshot was rejected")
    return _official_density_loaded

func set_official_density_enabled(enabled: bool) -> void:
    official_density_enabled = enabled
    reload_official_density_calibration()
    _apply_density_now()
    if auto_spawn_runtime:
        _replenish_traffic()

func _apply_density_now() -> void:
    if _density_model == null:
        return
    var anchor := _anchor_position()
    if not density_enabled:
        max_vehicles = _base_max_vehicles
        _current_density_factor = 1.0
        _current_sector = str(_density_model.call("nearest_sector", _corridor_anchors, anchor))
        _reset_current_official_calibration()
        return

    var time_component := float(_density_model.call("time_factor", simulation_hour))
    var spatial_component := float(_density_model.call("spatial_factor", _roads, anchor))
    _current_density_factor = time_component * spatial_component
    _current_sector = str(_density_model.call("nearest_sector", _corridor_anchors, anchor))
    max_vehicles = int(_density_model.call("target_vehicle_count", _base_max_vehicles, simulation_hour, _roads, anchor))
    _update_current_official_calibration(anchor)
    _trim_excess_traffic(max_vehicles)

func _update_current_official_calibration(anchor: Vector3) -> void:
    _reset_current_official_calibration()
    if not _official_density_loaded or _density_model == null:
        return
    var calibration: Dictionary = _density_model.call("official_calibration_for", anchor)
    _current_official_density_available = bool(calibration.get("available", false))
    if not _current_official_density_available:
        return
    _current_official_density_factor = float(calibration.get("factor", 1.0))
    _current_official_density_sample_count = int(calibration.get("sample_count", 0))
    _current_official_density_nearest_distance_m = float(calibration.get("nearest_distance_m", INF))
    var raw_ids: Variant = calibration.get("sensor_ids", PackedStringArray())
    if raw_ids is PackedStringArray:
        _current_official_density_sensor_ids = raw_ids
    elif raw_ids is Array:
        for raw_id: Variant in raw_ids:
            _current_official_density_sensor_ids.append(str(raw_id))

func _reset_current_official_calibration() -> void:
    _current_official_density_available = false
    _current_official_density_factor = 1.0
    _current_official_density_sample_count = 0
    _current_official_density_nearest_distance_m = INF
    _current_official_density_sensor_ids = PackedStringArray()

func is_official_density_loaded() -> bool:
    return _official_density_loaded

func is_official_density_available_here() -> bool:
    return _current_official_density_available

func get_official_density_sensor_count() -> int:
    if _density_model == null:
        return 0
    return int(_density_model.call("get_official_sensor_count"))

func get_official_density_capture_timestamp() -> String:
    if _density_model == null:
        return ""
    return str(_density_model.call("get_official_capture_timestamp"))

func get_official_density_factor() -> float:
    return _current_official_density_factor

func get_official_density_sample_count() -> int:
    return _current_official_density_sample_count

func get_official_density_nearest_distance_m() -> float:
    return _current_official_density_nearest_distance_m

func get_official_density_sensor_ids() -> PackedStringArray:
    return _current_official_density_sensor_ids.duplicate()
