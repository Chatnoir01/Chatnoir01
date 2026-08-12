extends Node

@export_file("*.json") var service_data_path: String = "res://data/vehicle_services/current.game.json"
@export_file("*.json") var playable_runtime_path: String = "res://data/osm/vertical_slice_01.game.json"
@export var car_path: NodePath = NodePath("../PrototypeCar")
@export var interaction_radius_m: float = 14.0
@export var full_repair_delay_s: float = 3.5

const BASE_GARAGE_REPAIR_EUR := 35.0

var _services: Array[Dictionary] = []
var _active_services: Array[Dictionary] = []
var _playable_bounds: Array = []
var _car: Node3D = null
var _service_state: String = "idle"
var _service_ready_at_s: float = 0.0
var _service_quote_eur: float = 0.0
var _service_name: String = ""


func _ready() -> void:
    _car = get_node_or_null(car_path) as Node3D
    _load_runtime_data()
    print(
        "Grand Bruxelles vehicle services: %d OSM services, %d active in current runtime, %d active garages" %
        [get_service_count(), get_active_service_count(), get_active_garage_count()]
    )


func _process(_delta: float) -> void:
    if _service_state != "requested" or _car == null:
        return
    var now_seconds := float(Time.get_ticks_msec()) / 1000.0
    if now_seconds < _service_ready_at_s:
        return
    if _car.has_method("repair_vehicle"):
        _car.call("repair_vehicle", 100.0)
    _service_state = "completed"


func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.keycode == KEY_G:
        request_full_repair()


func _load_runtime_data() -> void:
    _services.clear()
    _active_services.clear()
    _playable_bounds.clear()

    var service_data := _read_json(service_data_path)
    var runtime_data := _read_json(playable_runtime_path)
    var raw_bounds: Variant = runtime_data.get("bounds_m", [])
    if raw_bounds is Array and raw_bounds.size() >= 4:
        _playable_bounds = (raw_bounds as Array).duplicate()
    configure_data(service_data, _playable_bounds)


func configure_data(service_data: Dictionary, playable_bounds: Array) -> void:
    _services.clear()
    _active_services.clear()
    _playable_bounds = playable_bounds.duplicate()

    var raw_services: Variant = service_data.get("services", [])
    if not raw_services is Array:
        return
    for raw_service: Variant in raw_services:
        if typeof(raw_service) != TYPE_DICTIONARY:
            continue
        var service: Dictionary = (raw_service as Dictionary).duplicate(true)
        if not _service_has_position(service):
            continue
        var point: Vector3 = _service_position(service)
        service["runtime_active"] = _point_inside_bounds(point)
        _services.append(service)
        if bool(service["runtime_active"]):
            _active_services.append(service)


func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary


func _service_has_position(service: Dictionary) -> bool:
    var raw_point: Variant = service.get("point", null)
    return raw_point is Array and raw_point.size() >= 2


func _service_position(service: Dictionary) -> Vector3:
    var raw_point: Array = service.get("point", [])
    return Vector3(float(raw_point[0]), 0.68, float(raw_point[1]))


func _point_inside_bounds(point: Vector3) -> bool:
    if _playable_bounds.size() < 4:
        return false
    return (
        point.x >= float(_playable_bounds[0])
        and point.z >= float(_playable_bounds[1])
        and point.x <= float(_playable_bounds[2])
        and point.z <= float(_playable_bounds[3])
    )


func nearest_active_service(position: Vector3, kind: String = "") -> Dictionary:
    var best: Dictionary = {}
    var best_distance := INF
    for service: Dictionary in _active_services:
        if not kind.is_empty() and str(service.get("kind", "")) != kind:
            continue
        if not _service_has_position(service):
            continue
        var service_position := _service_position(service)
        var distance := position.distance_to(service_position)
        if distance < best_distance:
            best_distance = distance
            best = service.duplicate(true)
            best["distance_m"] = distance
    return best


func get_nearest_service_for_vehicle() -> Dictionary:
    if _car == null:
        return {}
    return nearest_active_service(_car.global_position)


func get_nearest_garage_for_vehicle() -> Dictionary:
    if _car == null:
        return {}
    return nearest_active_service(_car.global_position, "garage")


func estimate_full_repair_quote(body_damage: float, mechanical_damage: float) -> float:
    var body := clampf(body_damage, 0.0, 100.0)
    var mechanical := clampf(mechanical_damage, 0.0, 100.0)
    return round(BASE_GARAGE_REPAIR_EUR + body * 0.65 + mechanical * 1.10)


func request_full_repair(now_seconds: float = -1.0) -> bool:
    if _car == null or _service_state == "requested":
        return false
    var garage := get_nearest_garage_for_vehicle()
    if garage.is_empty() or float(garage.get("distance_m", INF)) > interaction_radius_m:
        return false
    if _car.has_method("get_speed_kmh") and float(_car.call("get_speed_kmh")) > 1.0:
        return false
    if _car.has_method("get_vehicle_health") and float(_car.call("get_vehicle_health")) >= 99.99:
        return false

    var body_damage := 0.0
    var mechanical_damage := 0.0
    if _car.has_method("get_vehicle_body_damage"):
        body_damage = float(_car.call("get_vehicle_body_damage"))
    if _car.has_method("get_vehicle_mechanical_damage"):
        mechanical_damage = float(_car.call("get_vehicle_mechanical_damage"))

    if now_seconds < 0.0:
        now_seconds = float(Time.get_ticks_msec()) / 1000.0
    _service_quote_eur = estimate_full_repair_quote(body_damage, mechanical_damage)
    _service_name = str(garage.get("name", "Garage"))
    _service_ready_at_s = now_seconds + maxf(0.0, full_repair_delay_s)
    _service_state = "requested"
    return true


func process_service_at(now_seconds: float) -> bool:
    if _service_state != "requested" or now_seconds < _service_ready_at_s or _car == null:
        return false
    if _car.has_method("repair_vehicle"):
        _car.call("repair_vehicle", 100.0)
    _service_state = "completed"
    return true


func reset_service_state() -> void:
    _service_state = "idle"
    _service_ready_at_s = 0.0
    _service_quote_eur = 0.0
    _service_name = ""


func get_service_count() -> int:
    return _services.size()


func get_active_service_count() -> int:
    return _active_services.size()


func get_active_garage_count() -> int:
    var count := 0
    for service: Dictionary in _active_services:
        if str(service.get("kind", "")) == "garage":
            count += 1
    return count


func get_service_state() -> String:
    return _service_state


func get_service_quote_eur() -> float:
    return _service_quote_eur


func get_service_name() -> String:
    return _service_name


func get_service_remaining_seconds() -> float:
    if _service_state != "requested":
        return 0.0
    return maxf(0.0, _service_ready_at_s - float(Time.get_ticks_msec()) / 1000.0)
